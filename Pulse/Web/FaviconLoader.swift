import AppKit

/// Fetches and caches favicons per host.
final class FaviconLoader {
    static let shared = FaviconLoader()

    /// Evaluated in the page: the icon it declares, or an empty string.
    static let declaredIconScript = """
        (document.querySelector("link[rel~='icon']") \
        || document.querySelector("link[rel='apple-touch-icon']"))?.href ?? ""
        """

    private var iconsByHost: [String: NSImage] = [:]

    func favicon(forPage pageURL: URL, declaredIconURL: URL?) async -> NSImage? {
        guard let host = pageURL.host() else { return nil }
        if let icon = iconsByHost[host] { return icon }

        let candidates = [declaredIconURL, URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL]
        for case let iconURL? in candidates {
            guard let (data, _) = try? await URLSession.shared.data(from: iconURL),
                  let icon = NSImage(data: data), icon.isValid
            else { continue }
            iconsByHost[host] = icon
            return icon
        }
        return nil
    }
}
