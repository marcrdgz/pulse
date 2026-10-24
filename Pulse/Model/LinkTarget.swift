import AppKit

/// Where a clicked link opens, following Safari and Chrome: ⌘- or middle-click opens a background tab,
/// adding ⇧ brings it to the front. ⇧-click alone opens it in Peek, like Arc.
enum LinkTarget: Equatable {
    /// Where the page asked: the same tab, or a new foreground one for `target=_blank`.
    case asRequested
    case newTab(activate: Bool)
    case peek

    /// `buttonMask` is what `WKNavigationAction.buttonNumber` reports on macOS despite its name:
    /// 1 for the left button, 2 for the right, 4 for the middle.
    init(isLinkClick: Bool, buttonMask: Int, modifierFlags: NSEvent.ModifierFlags) {
        let isMiddleClick = buttonMask & 4 != 0
        let modifiers = modifierFlags.intersection([.command, .option, .control, .shift])
        if isLinkClick, isMiddleClick || modifiers.contains(.command) {
            self = .newTab(activate: modifiers.contains(.shift))
        } else if isLinkClick, modifiers == .shift {
            self = .peek
        } else {
            self = .asRequested
        }
    }
}

extension URL {
    /// Schemes like `mailto:`, `zoommtg:` or `itms-apps:` that WebKit can't load and another app handles.
    var opensInOtherApp: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return !["http", "https", "about", "data", "blob", "file", "javascript"].contains(scheme)
    }

    /// The same host, or one a subdomain of the other (`github.com` and `gist.github.com`), so links
    /// within a site stay in a pinned tab while links to `calendar.google.com` from Gmail peek.
    func isSameSite(as other: URL) -> Bool {
        guard let host = displayHost, let otherHost = other.displayHost else { return false }
        return host == otherHost || host.hasSuffix("." + otherHost) || otherHost.hasSuffix("." + host)
    }
}
