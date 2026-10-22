import Foundation

/// Pages Pulse draws itself instead of loading in WebKit, like Chrome's `chrome://` pages.
enum InternalPage: String {
    case history
    case downloads

    /// Accepts `chrome://` too, so muscle memory from Chrome keeps working.
    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "pulse" || scheme == "chrome",
              let page = InternalPage(rawValue: url.host()?.lowercased() ?? "")
        else { return nil }
        self = page
    }

    var url: URL { URL(string: "pulse://\(rawValue)")! }

    var title: String {
        switch self {
        case .history: "History"
        case .downloads: "Downloads"
        }
    }

    var symbol: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .downloads: "arrow.down.circle"
        }
    }
}

extension URL {
    /// Pages that belong in history and get web views; excludes `about:`, `data:` and internal pages.
    var isWebPage: Bool {
        scheme == "http" || scheme == "https"
    }
}
