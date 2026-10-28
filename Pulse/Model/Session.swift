import Foundation
import OSLog

/// The persisted state of the sidebar: favorites, spaces with their tabs, and what was active.
struct Session: Codable, Equatable {
    struct SavedTab: Codable, Equatable {
        var id: UUID
        var url: URL
        var title: String
        var customTitle: String?
        var pinnedURL: URL?
    }

    struct SavedSpace: Codable, Equatable {
        var id: UUID
        var name: String
        /// Raw `SpaceTheme`; unknown values fall back to the default theme.
        var theme: String
        var icon: String? = nil
        var pinnedTabs: [SavedTab]
        var todayTabs: [SavedTab]
        var activeTabID: UUID?
        var splits: [TabSplit]? = nil
        /// `nil` for the default profile, as in sessions saved before profiles existed.
        var profileID: UUID? = nil
    }

    /// A profile other than the default one, with its favorites.
    struct SavedProfile: Codable, Equatable {
        var id: UUID
        var name: String
        var favorites: [SavedTab]
    }

    /// The default profile's.
    var favorites: [SavedTab]
    var spaces: [SavedSpace]
    var activeSpaceID: UUID?
    var profiles: [SavedProfile]

    init(favorites: [SavedTab], spaces: [SavedSpace], activeSpaceID: UUID?, profiles: [SavedProfile] = []) {
        self.favorites = favorites
        self.spaces = spaces
        self.activeSpaceID = activeSpaceID
        self.profiles = profiles
    }

    private enum CodingKeys: String, CodingKey {
        case favorites, spaces, activeSpaceID, profiles
        // Sessions saved before spaces existed.
        case pinnedTabs, todayTabs, activeTabID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.spaces) {
            favorites = try container.decode([SavedTab].self, forKey: .favorites)
            spaces = try container.decode([SavedSpace].self, forKey: .spaces)
            activeSpaceID = try container.decodeIfPresent(UUID.self, forKey: .activeSpaceID)
            profiles = try container.decodeIfPresent([SavedProfile].self, forKey: .profiles) ?? []
            return
        }
        // Before spaces, pinned tabs were a favicon grid: they become favorites, the rest a "Home" space.
        let home = SavedSpace(
            id: UUID(),
            name: "Home",
            theme: SpaceTheme.purple.rawValue,
            pinnedTabs: [],
            todayTabs: try container.decode([SavedTab].self, forKey: .todayTabs),
            activeTabID: try container.decodeIfPresent(UUID.self, forKey: .activeTabID)
        )
        favorites = try container.decode([SavedTab].self, forKey: .pinnedTabs)
        spaces = [home]
        activeSpaceID = home.id
        profiles = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(favorites, forKey: .favorites)
        try container.encode(spaces, forKey: .spaces)
        try container.encodeIfPresent(activeSpaceID, forKey: .activeSpaceID)
        try container.encode(profiles, forKey: .profiles)
    }
}

struct SessionStore {
    let fileURL: URL

    static var standard: SessionStore {
        let directory = URL.pulseSupportDirectory
        return SessionStore(fileURL: directory.appending(path: "session.json"))
    }

    /// The file this store moves an unreadable session to, so the next save can't destroy it.
    var backupURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
    }

    func load() -> Session? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(Session.self, from: data)
        } catch {
            Logger.session.error("Unreadable session, moving it aside: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            return nil
        }
    }

    func save(_ session: Session) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(session).write(to: fileURL, options: .atomic)
    }
}
