import Foundation

/// The persisted state of the sidebar: which tabs exist, which are pinned and which is active.
struct Session: Codable, Equatable {
    struct SavedTab: Codable, Equatable {
        var id: UUID
        var url: URL
        var title: String
        var customTitle: String?
        var pinnedURL: URL?
    }

    var pinnedTabs: [SavedTab]
    var todayTabs: [SavedTab]
    var activeTabID: UUID?
}

struct SessionStore {
    let fileURL: URL

    static var standard: SessionStore {
        let directory = URL.applicationSupportDirectory.appending(path: "Pulse", directoryHint: .isDirectory)
        return SessionStore(fileURL: directory.appending(path: "session.json"))
    }

    func load() -> Session? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    func save(_ session: Session) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(session).write(to: fileURL, options: .atomic)
    }
}
