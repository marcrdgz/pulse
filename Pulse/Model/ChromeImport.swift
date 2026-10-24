import CommonCrypto
import Foundation
import Security
import SQLite3

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
    case keychainAccessDenied

    var errorDescription: String? {
        switch self {
        case .unreadableBookmarks: "Pulse couldn't read Chrome's bookmarks."
        case .unreadableHistory: "Pulse couldn't read Chrome's history."
        case .unreadableCookies: "Pulse couldn't read Chrome's cookies."
        case .keychainAccessDenied:
            "Pulse needs your permission to read Chrome's cookies. Import again and choose Allow when macOS asks to use “Chrome Safe Storage”."
        }
    }
}

/// Reads Chrome's data folder: its profiles and each profile's bookmarks, history and cookies.
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
    /// domain, path, expiry, `Secure`, `HttpOnly` and `SameSite`. Chrome encrypts the values with
    /// a key it keeps in the login keychain, so macOS asks the user to allow Pulse to read it.
    static func cookies(of profile: ChromeProfile) throws -> [HTTPCookie] {
        try cookies(of: profile) { try safeStoragePassword() }
    }

    /// `password` is Chrome's keychain secret. It's asked for only after the database was read,
    /// so a profile without cookies never shows the keychain prompt.
    static func cookies(of profile: ChromeProfile, password: () throws -> Data) throws -> [HTTPCookie] {
        let database = try withCopy(of: profile, file: "Cookies", failure: .unreadableCookies) {
            try ChromeCookieDatabase(path: $0.path)
        }
        guard !database.rows.isEmpty else { return [] }
        let decryptor = try ChromeCookieDecryptor(password: password())
        let now = Date()
        var decryptedAny = false
        var failedAny = false
        let cookies = database.rows.compactMap { row -> HTTPCookie? in
            if let expiry = row.expiry, expiry <= now { return nil }
            var value = row.value
            if !row.encryptedValue.isEmpty {
                guard let decrypted = decryptor.decrypt(row.encryptedValue, hasHostHash: database.hasHostHash) else {
                    failedAny = true
                    return nil
                }
                decryptedAny = true
                value = decrypted
            }
            return row.cookie(value: value)
        }
        // A wrong key fails every value; a few undecryptable ones are only skipped.
        if failedAny && !decryptedAny { throw ChromeImportError.unreadableCookies }
        return cookies
    }

    /// The password Chrome derives its cookie key from, stored under "Chrome Safe Storage".
    private static func safeStoragePassword() throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Chrome Safe Storage",
            kSecAttrAccount: "Chrome",
            kSecReturnData: true,
        ]
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            guard let password = item as? Data else { throw ChromeImportError.unreadableCookies }
            return password
        // Chrome never saved a key, so there's nothing the user could allow.
        case errSecItemNotFound: throw ChromeImportError.unreadableCookies
        // Deny in the keychain prompt, or the prompt couldn't be shown.
        default: throw ChromeImportError.keychainAccessDenied
        }
    }

    /// Runs `body` on a copy of the profile's `History` database. The copy is deleted afterwards.
    static func withHistoryCopy<Result>(of profile: ChromeProfile, _ body: (URL) throws -> Result) throws -> Result {
        try withCopy(of: profile, file: "History", failure: .unreadableHistory, body)
    }

    /// Chrome locks its databases while running, and reading a copy can't damage them.
    private static func withCopy<Result>(
        of profile: ChromeProfile,
        file: String,
        failure: ChromeImportError,
        _ body: (URL) throws -> Result
    ) throws -> Result {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ChromeImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appending(path: file)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: profile.directory.appending(path: file), to: copy)
        } catch {
            throw failure
        }
        return try body(copy)
    }
}

/// The rows of Chrome's `Cookies` database that WebKit can hold.
private struct ChromeCookieDatabase {
    struct Row {
        let domain: String
        let name: String
        let value: String
        let encryptedValue: Data
        let path: String
        /// Nil for session cookies.
        let expiry: Date?
        let isSecure: Bool
        let isHTTPOnly: Bool
        /// Chrome's `CookieSameSite`: -1 unspecified, 0 none, 1 lax, 2 strict.
        let sameSite: Int

        func cookie(value: String) -> HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: path,
                .name: name,
                .value: value,
            ]
            if let expiry { properties[.expires] = expiry } else { properties[.discard] = "TRUE" }
            if isSecure { properties[.secure] = "TRUE" }
            if isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            // WebKit treats a missing policy as None, which also covers Chrome's unspecified.
            switch sameSite {
            case 1: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax.rawValue
            case 2: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict.rawValue
            default: break
            }
            return HTTPCookie(properties: properties)
        }
    }

    let rows: [Row]
    /// From schema version 24 on, each decrypted value starts with a SHA-256 of its domain.
    let hasHostHash: Bool

    init(path: String) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ChromeImportError.unreadableCookies
        }
        hasHostHash = try Self.query(db, "SELECT value FROM meta WHERE key = 'version'") {
            (Int(Self.text($0, 0)) ?? 0) >= 24
        }.first ?? false
        // Partitioned cookies (CHIPS) are skipped: HTTPCookie can't say which site they belong to.
        rows = try Self.query(db, """
            SELECT host_key, name, value, encrypted_value, path, expires_utc, is_persistent,
                is_secure, is_httponly, samesite
            FROM cookies WHERE top_frame_site_key = ''
            """) { statement in
            // Chrome stores microseconds since 1601-01-01.
            let expiresUTC = sqlite3_column_int64(statement, 5)
            let isPersistent = sqlite3_column_int(statement, 6) != 0 && expiresUTC > 0
            return Row(
                domain: Self.text(statement, 0),
                name: Self.text(statement, 1),
                value: Self.text(statement, 2),
                encryptedValue: sqlite3_column_blob(statement, 3).map {
                    Data(bytes: $0, count: Int(sqlite3_column_bytes(statement, 3)))
                } ?? Data(),
                path: Self.text(statement, 4),
                expiry: isPersistent ? Date(timeIntervalSince1970: Double(expiresUTC) / 1_000_000 - 11_644_473_600) : nil,
                isSecure: sqlite3_column_int(statement, 7) != 0,
                isHTTPOnly: sqlite3_column_int(statement, 8) != 0,
                sameSite: Int(sqlite3_column_int(statement, 9))
            )
        }
    }

    private static func query<T>(_ db: OpaquePointer?, _ sql: String, row: (OpaquePointer?) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ChromeImportError.unreadableCookies
        }
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(row(statement))
        }
        return results
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }
}

/// Chrome's macOS cookie encryption: AES-128-CBC with a PBKDF2 key from the keychain password.
private struct ChromeCookieDecryptor {
    private static let prefix = Data("v10".utf8)
    private static let hostHashLength = 32
    private let key: Data

    init(password: Data) throws {
        var key = Data(count: kCCKeySizeAES128)
        let salt = Data("saltysalt".utf8)
        let status = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), kCCKeySizeAES128
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw ChromeImportError.unreadableCookies }
        self.key = key
    }

    func decrypt(_ encrypted: Data, hasHostHash: Bool) -> String? {
        guard encrypted.starts(with: Self.prefix) else { return nil }
        let ciphertext = encrypted.dropFirst(Self.prefix.count)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var plaintext = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var length = 0
        let status = plaintext.withUnsafeMutableBytes { plaintextBytes in
            ciphertext.withUnsafeBytes { ciphertextBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                            ciphertextBytes.baseAddress, ciphertext.count,
                            plaintextBytes.baseAddress, plaintextBytes.count, &length
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        let value = plaintext.prefix(length).dropFirst(hasHostHash ? Self.hostHashLength : 0)
        return String(data: value, encoding: .utf8)
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
