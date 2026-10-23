import Foundation

/// Installs from the Chrome Web Store the way Chrome does: by extension ID, as a CRX package.
enum ChromeWebStore {
    static let homeURL = URL(string: "https://chromewebstore.google.com")!

    enum PackageError: LocalizedError {
        case notACRXFile
        case truncated

        var errorDescription: String? {
            switch self {
            case .notACRXFile: "The file isn't a Chrome extension package."
            case .truncated: "The extension package is incomplete."
            }
        }
    }

    /// The ID of the extension a store page shows, e.g.
    /// `chromewebstore.google.com/detail/bitwarden-password-manager/nngceckbapebfimnlniiiahkandclblb`.
    static func extensionID(fromStorePage url: URL) -> String? {
        let isStore = url.host() == "chromewebstore.google.com"
            || (url.host() == "chrome.google.com" && url.pathComponents.dropFirst().first == "webstore")
        guard isStore, url.pathComponents.contains("detail") else { return nil }
        return url.pathComponents.last { isExtensionID($0) }
    }

    /// Chrome IDs are 32 letters from a to p.
    static func isExtensionID(_ string: String) -> Bool {
        string.count == 32 && string.allSatisfy { ("a"..."p").contains($0) }
    }

    /// Chrome's update service, which redirects to the latest CRX. `prodversion` gates extensions
    /// that require a minimum Chrome version, so it claims a recent one.
    static func packageURL(forExtension id: String) -> URL {
        var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
        components.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: "140.0"),
            URLQueryItem(name: "acceptformat", value: "crx2,crx3"),
            URLQueryItem(name: "x", value: "id=\(id)&uc"),
        ]
        return components.url!
    }

    static func isPackage(_ data: Data) -> Bool {
        data.starts(with: Data("Cr24".utf8))
    }

    /// A CRX is a ZIP archive behind a signed header; WebKit loads the archive itself.
    static func zipArchive(fromPackage data: Data) throws -> Data {
        guard isPackage(data) else { throw PackageError.notACRXFile }
        let bytes = [UInt8](data)
        func uint32(at offset: Int) throws -> Int {
            guard offset + 4 <= bytes.count else { throw PackageError.truncated }
            return bytes[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | Int($1) }
        }
        let headerEnd = switch try uint32(at: 4) {
        // CRX3: a protobuf header of the given size.
        case 3: try 12 + uint32(at: 8)
        // CRX2: a public key and a signature, each preceded by its length.
        case 2: try 16 + uint32(at: 8) + uint32(at: 12)
        default: throw PackageError.notACRXFile
        }
        guard headerEnd < bytes.count else { throw PackageError.truncated }
        return Data(bytes[headerEnd...])
    }
}
