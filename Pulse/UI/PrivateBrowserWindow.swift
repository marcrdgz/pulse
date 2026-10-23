import SwiftUI

/// A window whose browser keeps nothing: closing it drops its cookies, storage and tabs.
struct PrivateBrowserWindow: View {
    static let id = "private"

    let contentBlocker: ContentBlocker
    let preferences: Preferences
    /// Created once per window; a view's initializer runs again on every update.
    @State private var browser: Browser?

    var body: some View {
        if let browser {
            BrowserWindow()
                .environment(browser)
                .focusedSceneValue(\.browser, browser)
        } else {
            Color.clear
                .onAppear { browser = .makePrivate(contentBlocker: contentBlocker, preferences: preferences) }
        }
    }
}

extension FocusedValues {
    /// The browser of the key window, which menu commands act on.
    var browser: Browser? {
        get { self[BrowserKey.self] }
        set { self[BrowserKey.self] = newValue }
    }

    private struct BrowserKey: FocusedValueKey {
        typealias Value = Browser
    }
}
