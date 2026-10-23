import Foundation

/// A Chrome profile folder, e.g. `…/Chrome/Default` or `…/Chrome/Profile 1`.
struct ChromeProfile: Identifiable, Hashable {
    let directory: URL
    let name: String
    /// The signed-in Google account, if any; tells apart profiles with the same name.
    let email: String?

    var id: URL { directory }
}

struct Bookmark: Equatable {
    let title: String
    let url: URL
}

struct ChromeImportItems: OptionSet {
    let rawValue: Int

    static let history = ChromeImportItems(rawValue: 1 << 0)
    static let bookmarks = ChromeImportItems(rawValue: 1 << 1)
    static let cookies = ChromeImportItems(rawValue: 1 << 2)
}

struct ChromeImportSummary: Equatable {
    var bookmarkCount = 0
    var cookieCount = 0
    var importedHistory = false
}

enum ChromeImportError: LocalizedError {
    case unreadableBookmarks
    case unreadableHistory
    case unreadableCookies

    var errorDescription: String? {
        switch self {
        case .unreadableBookmarks: "Pulse couldn't read Chrome's bookmarks."
        case .unreadableHistory: "Pulse couldn't read Chrome's history."
        case .unreadableCookies: "Pulse couldn't read Chrome's cookies."
        }
    }
}

/// Reads Chrome's data folder: its profiles and each profile's bookmarks and history.
enum ChromeImport {
    /// Where Chrome keeps its profiles. In the sandbox the home directory is the app's container,
    /// so this resolves the real one; reading it still needs the user to pick it in an open panel.
    static var defaultDirectory: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(filePath: home, directoryHint: .isDirectory)
            .appending(path: "Library/Application Support/Google/Chrome", directoryHint: .isDirectory)
    }

    /// The last used profile first, then by name. Empty when `chromeDirectory` isn't Chrome's folder.
    static func profiles(in chromeDirectory: URL) -> [ChromeProfile] {
        let state = (try? Data(contentsOf: chromeDirectory.appending(path: "Local State")))
            .flatMap { try? JSONDecoder().decode(LocalState.self, from: $0) }
        let lastUsed = state?.profile.lastUsed
        let profiles = (state?.profile.infoCache ?? [:]).compactMap { folder, info -> (String, ChromeProfile)? in
            let directory = chromeDirectory.appending(path: folder, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
            let email = info.userName.flatMap { $0.isEmpty ? nil : $0 }
            return (folder, ChromeProfile(directory: directory, name: info.name, email: email))
        }
        if profiles.isEmpty {
            // No usable "Local State": fall back to the profile every Chrome install has.
            let directory = chromeDirectory.appending(path: "Default", directoryHint: .isDirectory)
            let hasDefault = FileManager.default.fileExists(atPath: directory.appending(path: "Preferences").path)
            return hasDefault ? [ChromeProfile(directory: directory, name: "Default", email: nil)] : []
        }
        return profiles
            .sorted { ($0.0 == lastUsed ? 0 : 1, $0.1.name) < ($1.0 == lastUsed ? 0 : 1, $1.1.name) }
            .map(\.1)
    }

    /// The bookmarks bar in order, with folders flattened in place (Pulse has no folders yet).
    /// Only web links, each once.
    static func bookmarkBar(of profile: ChromeProfile) throws -> [Bookmark] {
        let file = profile.directory.appending(path: "Bookmarks")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let bookmarks: BookmarksFile
        do {
            bookmarks = try JSONDecoder().decode(BookmarksFile.self, from: Data(contentsOf: file))
        } catch {
            throw ChromeImportError.unreadableBookmarks
        }
        var seen: Set<URL> = []
        return bookmarks.roots.bookmarkBar.bookmarks.filter { seen.insert($0.url).inserted }
    }

    /// The profile's cookies, ready for WebKit's cookie store. Every attribute must carry over:
    /// domain, path, expiry, `Secure`, `HttpOnly` and `SameSite`.
    static func cookies(of profile: ChromeProfile) throws -> [HTTPCookie] {
        // TODO: Read the profile's cookies.
        throw ChromeImportError.unreadableCookies
    }

    /// Runs `body` on a copy of the profile's `History` database: Chrome locks its own while running,
    /// and reading a copy can't damage it. The copy is deleted afterwards.
    static func withHistoryCopy<Result>(of profile: ChromeProfile, _ body: (URL) throws -> Result) throws -> Result {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ChromeImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appending(path: "History")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: profile.directory.appending(path: "History"), to: copy)
        } catch {
            throw ChromeImportError.unreadableHistory
        }
        return try body(copy)
    }
}

private struct LocalState: Decodable {
    struct Profiles: Decodable {
        let infoCache: [String: ProfileInfo]
        let lastUsed: String?

        private enum CodingKeys: String, CodingKey {
            case infoCache = "info_cache"
            case lastUsed = "last_used"
        }
    }

    struct ProfileInfo: Decodable {
        let name: String
        let userName: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case userName = "user_name"
        }
    }

    let profile: Profiles
}

private struct BookmarksFile: Decodable {
    struct Roots: Decodable {
        let bookmarkBar: BookmarkNode

        private enum CodingKeys: String, CodingKey {
            case bookmarkBar = "bookmark_bar"
        }
    }

    let roots: Roots
}

/// A link (has `url`) or a folder (has `children`).
private struct BookmarkNode: Decodable {
    let name: String
    let url: String?
    let children: [BookmarkNode]?

    var bookmarks: [Bookmark] {
        if let url = url.flatMap(URL.init(string:)) {
            return ["http", "https"].contains(url.scheme) ? [Bookmark(title: name, url: url)] : []
        }
        return (children ?? []).flatMap(\.bookmarks)
    }
}
