import Foundation
import Observation
import OSLog
import SQLite3

struct HistoryVisit: Identifiable, Equatable {
    let id: Int64
    let url: URL
    let title: String
    let date: Date
}

/// A visited URL with the counters suggestions are ranked by.
struct HistoryEntry: Equatable {
    let url: URL
    let title: String
    let visitCount: Int
    let typedCount: Int
    let lastVisit: Date
}

/// Browsing history in SQLite, like Chrome's: one row per URL with counters (for suggestions)
/// and one per visit (for the history page).
@Observable
final class HistoryStore {
    /// Bumped on every change so views showing history refresh.
    private(set) var revision = 0

    @ObservationIgnored private let connection: Connection
    private var db: OpaquePointer? { connection.handle }
    /// Revisits of a URL closer than this (reloads, redirects back) count as one visit.
    @ObservationIgnored private let revisitInterval: TimeInterval = 60

    /// `":memory:"` keeps the history in memory, for tests.
    init?(path: String) {
        guard let connection = Connection(path: path) else {
            Logger.history.error("Couldn't open history at \(path, privacy: .public)")
            return nil
        }
        self.connection = connection
        execute("PRAGMA foreign_keys = ON")
        execute("PRAGMA journal_mode = WAL")
        execute("""
            CREATE TABLE IF NOT EXISTS urls (
                id INTEGER PRIMARY KEY,
                url TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL DEFAULT '',
                visit_count INTEGER NOT NULL DEFAULT 0,
                typed_count INTEGER NOT NULL DEFAULT 0,
                last_visit REAL NOT NULL DEFAULT 0
            )
            """)
        execute("""
            CREATE TABLE IF NOT EXISTS visits (
                id INTEGER PRIMARY KEY,
                url_id INTEGER NOT NULL REFERENCES urls(id) ON DELETE CASCADE,
                time REAL NOT NULL
            )
            """)
        execute("CREATE INDEX IF NOT EXISTS visits_time ON visits(time)")
        execute("CREATE INDEX IF NOT EXISTS visits_url ON visits(url_id)")
    }

    static func standard() -> HistoryStore? {
        let directory = URL.applicationSupportDirectory.appending(path: "Pulse", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return HistoryStore(path: directory.appending(path: "History.sqlite").path)
    }

    // MARK: Recording

    func recordVisit(url: URL, title: String, at date: Date = .now) {
        execute(
            "INSERT INTO urls (url, title, last_visit) VALUES (?, ?, 0) ON CONFLICT(url) DO NOTHING",
            [.text(url.absoluteString), .text(title)]
        )
        let lastVisit = query("SELECT last_visit FROM urls WHERE url = ?", [.text(url.absoluteString)]) {
            Date(timeIntervalSince1970: $0.double(0))
        }.first ?? .distantPast

        if date.timeIntervalSince(lastVisit) >= revisitInterval {
            execute(
                "INSERT INTO visits (url_id, time) SELECT id, ? FROM urls WHERE url = ?",
                [.double(date.timeIntervalSince1970), .text(url.absoluteString)]
            )
            execute(
                "UPDATE urls SET visit_count = visit_count + 1 WHERE url = ?",
                [.text(url.absoluteString)]
            )
        }
        execute(
            "UPDATE urls SET last_visit = ?, title = CASE WHEN ? = '' THEN title ELSE ? END WHERE url = ?",
            [.double(date.timeIntervalSince1970), .text(title), .text(title), .text(url.absoluteString)]
        )
        revision += 1
    }

    func updateTitle(_ title: String, for url: URL) {
        guard !title.isEmpty else { return }
        execute("UPDATE urls SET title = ? WHERE url = ?", [.text(title), .text(url.absoluteString)])
        revision += 1
    }

    /// The user typed this address: typed URLs rank first and are completed inline, like in Chrome.
    func recordTyped(_ url: URL) {
        execute(
            "INSERT INTO urls (url, last_visit) VALUES (?, 0) ON CONFLICT(url) DO NOTHING",
            [.text(url.absoluteString)]
        )
        execute("UPDATE urls SET typed_count = typed_count + 1 WHERE url = ?", [.text(url.absoluteString)])
    }

    /// Merges a copy of Chrome's `History` database: web URLs with their counters, and their visits
    /// except subframe loads. Importing the same history again adds nothing.
    func importChromeHistory(from database: URL) -> Bool {
        guard execute("ATTACH DATABASE ? AS chrome", [.text(database.path)]) else { return false }
        defer { execute("DETACH DATABASE chrome") }
        // Chrome stores microseconds since 1601-01-01.
        let chromeTime = { (column: String) in "(\(column) / 1000000.0 - 11644473600)" }
        execute("BEGIN")
        let imported = execute("""
            INSERT INTO main.urls (url, title, visit_count, typed_count, last_visit)
            SELECT url, title, visit_count, typed_count, \(chromeTime("last_visit_time")) FROM chrome.urls
            WHERE hidden = 0 AND last_visit_time > 0 AND (url LIKE 'http://%' OR url LIKE 'https://%')
            ON CONFLICT(url) DO UPDATE SET
                title = CASE WHEN urls.title = '' THEN excluded.title ELSE urls.title END,
                visit_count = MAX(urls.visit_count, excluded.visit_count),
                typed_count = MAX(urls.typed_count, excluded.typed_count),
                last_visit = MAX(urls.last_visit, excluded.last_visit)
            """) && execute("""
            INSERT INTO main.visits (url_id, time)
            SELECT pulse_urls.id, \(chromeTime("chrome_visits.visit_time"))
            FROM chrome.visits AS chrome_visits
            JOIN chrome.urls AS chrome_urls ON chrome_urls.id = chrome_visits.url
            JOIN main.urls AS pulse_urls ON pulse_urls.url = chrome_urls.url
            WHERE (chrome_visits.transition & 255) NOT IN (3, 4)
            AND NOT EXISTS (
                SELECT 1 FROM main.visits
                WHERE url_id = pulse_urls.id AND time = \(chromeTime("chrome_visits.visit_time"))
            )
            """)
        execute(imported ? "COMMIT" : "ROLLBACK")
        revision += 1
        return imported
    }

    // MARK: Reading

    /// Newest first. Every whitespace-separated term must appear in the URL or title.
    func visits(matching text: String = "", limit: Int = 1000) -> [HistoryVisit] {
        let (condition, bindings) = termsCondition(text)
        return query(
            """
            SELECT visits.id, urls.url, urls.title, visits.time FROM visits
            JOIN urls ON urls.id = visits.url_id
            WHERE \(condition) ORDER BY visits.time DESC LIMIT ?
            """,
            bindings + [.int(limit)]
        ) { row in
            URL(string: row.text(1)).map {
                HistoryVisit(id: row.int(0), url: $0, title: row.text(2), date: Date(timeIntervalSince1970: row.double(3)))
            }
        }.compactMap { $0 }
    }

    /// Visited URLs matching every term: the most recent first without terms, otherwise the most
    /// used first, so a short input keeps addresses typed often among the candidates the caller ranks.
    func entries(matching text: String, limit: Int = 200, now: Date = .now) -> [HistoryEntry] {
        let (condition, bindings) = termsCondition(text)
        // `Omnibox.score` without the match bonus: typed and visit counts, faded by age.
        let order = bindings.isEmpty ? "last_visit DESC" : """
            (MIN(typed_count, 20) * 20 + MIN(visit_count, 30) * 5) * CASE
                WHEN :now - last_visit < 4 * 86400 THEN 1.0
                WHEN :now - last_visit < 14 * 86400 THEN 0.5
                WHEN :now - last_visit < 31 * 86400 THEN 0.25
                WHEN :now - last_visit < 90 * 86400 THEN 0.1
                ELSE 0.05
            END DESC, last_visit DESC
            """
        return query(
            """
            SELECT url, title, visit_count, typed_count, last_visit FROM urls
            WHERE (visit_count > 0 OR typed_count > 0) AND \(condition)
            ORDER BY \(order) LIMIT ?
            """,
            // SQLite numbers `:now` after the terms on first use, and reuses it after that.
            bindings + (bindings.isEmpty ? [] : [.double(now.timeIntervalSince1970)]) + [.int(limit)]
        ) { row in
            URL(string: row.text(0)).map {
                HistoryEntry(
                    url: $0,
                    title: row.text(1),
                    visitCount: Int(row.int(2)),
                    typedCount: Int(row.int(3)),
                    lastVisit: Date(timeIntervalSince1970: row.double(4))
                )
            }
        }.compactMap { $0 }
    }

    // MARK: Deleting

    func deleteVisits(_ ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        execute("DELETE FROM visits WHERE id IN (\(placeholders))", ids.map { .int($0) })
        pruneURLs()
    }

    /// Removes the URL and all its visits, e.g. ⇧⌦ on a suggestion.
    func deleteURL(_ url: URL) {
        execute("DELETE FROM urls WHERE url = ?", [.text(url.absoluteString)])
        revision += 1
    }

    /// Everything since `date`, or the whole history when `nil`.
    func deleteVisits(since date: Date?) {
        if let date {
            execute("DELETE FROM visits WHERE time >= ?", [.double(date.timeIntervalSince1970)])
        } else {
            execute("DELETE FROM visits")
            execute("DELETE FROM urls")
        }
        pruneURLs()
    }

    /// Keeps the per-URL counters in step with the remaining visits and drops URLs left without any.
    private func pruneURLs() {
        execute("""
            UPDATE urls SET
                visit_count = (SELECT COUNT(*) FROM visits WHERE url_id = urls.id),
                last_visit = COALESCE((SELECT MAX(time) FROM visits WHERE url_id = urls.id), 0)
            """)
        execute("DELETE FROM urls WHERE visit_count = 0")
        revision += 1
    }

    // MARK: SQLite

    enum Binding {
        case text(String)
        case double(Double)
        case int(Int64)

        static func int(_ value: Int) -> Binding { .int(Int64(value)) }
    }

    struct Row {
        fileprivate let statement: OpaquePointer?

        func text(_ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
        func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    }

    private func termsCondition(_ text: String) -> (String, [Binding]) {
        let terms = text.split(whereSeparator: \.isWhitespace).map { "%\($0)%" }
        guard !terms.isEmpty else { return ("1", []) }
        let condition = terms.map { _ in "(urls.url LIKE ? OR urls.title LIKE ?)" }.joined(separator: " AND ")
        return (condition, terms.flatMap { [Binding.text($0), .text($0)] })
    }

    @discardableResult
    private func execute(_ sql: String, _ bindings: [Binding] = []) -> Bool {
        guard let statement = prepare(sql, bindings) else { return false }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result != SQLITE_DONE && result != SQLITE_ROW {
            Logger.history.error("SQLite error: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return false
        }
        return true
    }

    private func query<T>(_ sql: String, _ bindings: [Binding], row transform: (Row) -> T) -> [T] {
        guard let statement = prepare(sql, bindings) else { return [] }
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(transform(Row(statement: statement)))
        }
        return results
    }

    private func prepare(_ sql: String, _ bindings: [Binding]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            Logger.history.error("SQLite error: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return nil
        }
        // SQLITE_TRANSIENT: SQLite copies the string before the Swift buffer goes away.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, binding) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch binding {
            case .text(let value): sqlite3_bind_text(statement, position, value, -1, transient)
            case .double(let value): sqlite3_bind_double(statement, position, value)
            case .int(let value): sqlite3_bind_int64(statement, position, value)
            }
        }
        return statement
    }
}

/// Owns the SQLite handle so it's closed when the store goes away; the store's own deinit
/// can't touch main-actor state.
private nonisolated final class Connection {
    let handle: OpaquePointer?

    init?(path: String) {
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }
}

private extension Logger {
    static let history = Logger(subsystem: "dev.doblefilo.pulse", category: "History")
}
