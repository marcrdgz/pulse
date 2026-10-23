import AppKit

/// Where a clicked link opens, following Safari and Chrome: ⌘- or middle-click opens a background tab,
/// adding ⇧ brings it to the front.
enum LinkTarget: Equatable {
    /// Where the page asked: the same tab, or a new foreground one for `target=_blank`.
    case asRequested
    case newTab(activate: Bool)

    /// `buttonMask` is what `WKNavigationAction.buttonNumber` reports on macOS despite its name:
    /// 1 for the left button, 2 for the right, 4 for the middle.
    init(isLinkClick: Bool, buttonMask: Int, modifierFlags: NSEvent.ModifierFlags) {
        let isMiddleClick = buttonMask & 4 != 0
        guard isLinkClick, isMiddleClick || modifierFlags.contains(.command) else {
            self = .asRequested
            return
        }
        self = .newTab(activate: modifierFlags.contains(.shift))
    }
}

extension URL {
    /// Schemes like `mailto:`, `zoommtg:` or `itms-apps:` that WebKit can't load and another app handles.
    var opensInOtherApp: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return !["http", "https", "about", "data", "blob", "file", "javascript"].contains(scheme)
    }
}
