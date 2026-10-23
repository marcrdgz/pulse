import AppKit

/// Fetches and caches favicons per host.
final class FaviconLoader {
    /// Cached on disk, which Clear Browsing Data empties along with history.
    static let shared = FaviconLoader(session: URLSession(configuration: .cookieless(cache: .shared)))
    /// For private windows: icons stay in memory instead of the shared disk cache.
    static let ephemeral = FaviconLoader(session: URLSession(configuration: .cookieless(cache: nil)))

    /// Icons are decoded in Pulse's own process, outside WebKit's sandbox, so larger files
    /// (no real favicon comes close) aren't handed to the image decoders at all.
    private static let maximumIconSize = 512 * 1024

    /// Evaluated in the page: the icon it declares, or an empty string.
    static let declaredIconScript = """
        (document.querySelector("link[rel~='icon']") \
        || document.querySelector("link[rel='apple-touch-icon']"))?.href ?? ""
        """

    private let session: URLSession
    private var iconsByHost: [String: NSImage] = [:]

    init(session: URLSession) {
        self.session = session
    }

    func favicon(forPage pageURL: URL, declaredIconURL: URL?) async -> NSImage? {
        guard let host = pageURL.host() else { return nil }
        if let icon = iconsByHost[host] { return icon }

        let candidates = [declaredIconURL, URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL]
        for case let iconURL? in candidates {
            guard let (data, _) = try? await session.data(from: iconURL),
                  data.count <= Self.maximumIconSize,
                  let icon = NSImage(data: data), icon.isValid
            else { continue }
            iconsByHost[host] = icon
            return icon
        }
        return nil
    }
}
