import Foundation
import SQLite3
import Testing
import WebKit
@testable import Pulse

struct ChromeImportTests {
    private let chromeDirectory = FileManager.default.temporaryDirectory
        .appending(path: "PulseTests-Chrome-\(UUID().uuidString)", directoryHint: .isDirectory)
    private let visitDate = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func listsProfilesLastUsedFirst() throws {
        try writeLocalState(lastUsed: "Profile 1")
        try makeProfile("Default")
        try makeProfile("Profile 1")

        let profiles = ChromeImport.profiles(in: chromeDirectory)
        #expect(profiles.map(\.name) == ["Work", "Personal"])
        #expect(profiles.map(\.email) == ["me@work.com", nil])
        #expect(ChromeImport.profiles(in: chromeDirectory.appending(path: "Default")).isEmpty)
    }

    @Test func importsBookmarksBarAsPinnedTabsInANewSpace() async throws {
        let profile = try makeProfile("Default")
        try writeBookmarks(in: profile)
        let browser = Browser()

        let summary = try await browser.importFromChrome(profile, items: .bookmarks)

        #expect(summary == ChromeImportSummary(bookmarkCount: 3))
        #expect(browser.activeSpace.name == "Chrome")
        #expect(browser.pinnedTabs.map(\.url.absoluteString) == ["https://a.com/", "https://b.com/", "https://c.com/"])
        let titles = browser.pinnedTabs.map(\.displayTitle)
        #expect(titles == ["A", "B", "C"])
        #expect(browser.pinnedTabs.filter(\.isPinned).count == 3)
    }

    @Test func importsHistoryWithoutSubframesAndOnlyOnce() async throws {
        let profile = try makeProfile("Default")
        try writeHistory(in: profile)
        let history = try #require(HistoryStore(path: ":memory:"))
        let browser = Browser(history: history)

        let summary = try await browser.importFromChrome(profile, items: [.history, .bookmarks])
        _ = try await browser.importFromChrome(profile, items: .history)

        #expect(summary == ChromeImportSummary(importedHistory: true))
        #expect(browser.spaces.count == 1)
        #expect(history.visits().map(\.url.absoluteString) == ["https://swift.org/", "https://swift.org/"])
        #expect(history.visits().first?.date == visitDate.addingTimeInterval(60))
        let entry = try #require(history.entries(matching: "").first)
        #expect(entry.title == "Swift")
        #expect(entry.visitCount == 2)
        #expect(entry.typedCount == 1)
        #expect(history.entries(matching: "").count == 1)
    }

    @Test func unreadableCookiesLeaveEverythingUnchanged() async throws {
        let profile = try makeProfile("Default")
        try writeBookmarks(in: profile)
        try writeHistory(in: profile)
        let history = try #require(HistoryStore(path: ":memory:"))
        let browser = Browser(history: history)
        let cookieStore = WKWebsiteDataStore.nonPersistent().httpCookieStore

        await #expect(throws: ChromeImportError.unreadableCookies) {
            try await browser.importFromChrome(profile, items: [.history, .bookmarks, .cookies], cookieStore: cookieStore)
        }
        #expect(browser.spaces.count == 1)
        #expect(history.visits().isEmpty)
    }

    @Test func showsOnboardingOnlyOnFirstLaunch() throws {
        let store = SessionStore(fileURL: chromeDirectory.appending(path: "session.json"))
        let preferences = Preferences()

        let browser = Browser(sessionStore: store, preferences: preferences)
        #expect(browser.isOnboardingPresented)
        #expect(browser.commandBar == nil)

        browser.finishOnboarding()
        #expect(browser.commandBar == .newTab)
        #expect(!Browser(sessionStore: store, preferences: preferences).isOnboardingPresented)
        #expect(!Browser().isOnboardingPresented)
    }

    // MARK: Fake Chrome folder

    @discardableResult
    private func makeProfile(_ folder: String) throws -> ChromeProfile {
        let directory = chromeDirectory.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ChromeProfile(directory: directory, name: folder, email: nil)
    }

    private func writeLocalState(lastUsed: String) throws {
        try FileManager.default.createDirectory(at: chromeDirectory, withIntermediateDirectories: true)
        try Data("""
            {"profile": {"last_used": "\(lastUsed)", "info_cache": {
                "Default": {"name": "Personal", "user_name": ""},
                "Profile 1": {"name": "Work", "user_name": "me@work.com"},
                "Profile 2": {"name": "Deleted", "user_name": ""}
            }}}
            """.utf8).write(to: chromeDirectory.appending(path: "Local State"))
    }

    private func writeBookmarks(in profile: ChromeProfile) throws {
        try Data("""
            {"roots": {
                "bookmark_bar": {"type": "folder", "name": "Bookmarks bar", "children": [
                    {"type": "url", "name": "A", "url": "https://a.com/"},
                    {"type": "folder", "name": "Folder", "children": [
                        {"type": "url", "name": "B", "url": "https://b.com/"},
                        {"type": "url", "name": "Bookmarklet", "url": "javascript:alert(1)"}
                    ]},
                    {"type": "url", "name": "A again", "url": "https://a.com/"},
                    {"type": "url", "name": "C", "url": "https://c.com/"}
                ]},
                "other": {"type": "folder", "name": "Other", "children": [
                    {"type": "url", "name": "Elsewhere", "url": "https://other.com/"}
                ]}
            }}
            """.utf8).write(to: profile.directory.appending(path: "Bookmarks"))
    }

    /// Chrome's schema, reduced to the columns Pulse reads.
    private func writeHistory(in profile: ChromeProfile) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(profile.directory.appending(path: "History").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let time = { (date: Date) in Int64((date.timeIntervalSince1970 + 11_644_473_600) * 1_000_000) }
        let sql = """
            CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER,
                typed_count INTEGER, last_visit_time INTEGER, hidden INTEGER DEFAULT 0);
            CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER, transition INTEGER);
            INSERT INTO urls VALUES (1, 'https://swift.org/', 'Swift', 2, 1, \(time(visitDate.addingTimeInterval(60))), 0);
            INSERT INTO urls VALUES (2, 'https://ads.example/frame', 'Ad', 1, 0, \(time(visitDate)), 1);
            INSERT INTO urls VALUES (3, 'chrome://settings/', 'Settings', 1, 0, \(time(visitDate)), 0);
            INSERT INTO visits VALUES (1, 1, \(time(visitDate)), 1);
            INSERT INTO visits VALUES (2, 1, \(time(visitDate.addingTimeInterval(60))), 805306368);
            INSERT INTO visits VALUES (3, 1, \(time(visitDate.addingTimeInterval(30))), 3);
            """
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }
}
