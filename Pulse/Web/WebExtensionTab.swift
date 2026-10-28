import AppKit
import WebKit

/// A tab as extensions see it through `chrome.tabs`.
extension Tab: WKWebExtensionTab {
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { browser }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        browser?.extensionTabs.firstIndex { $0 === self } ?? NSNotFound
    }

    func parentTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { opener }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { loadedWebView }

    func title(for context: WKWebExtensionContext) -> String? { displayTitle }

    func url(for context: WKWebExtensionContext) -> URL? { url }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !isLoading }

    func size(for context: WKWebExtensionContext) -> CGSize { loadedWebView?.bounds.size ?? .zero }

    func zoomFactor(for context: WKWebExtensionContext) -> Double { loadedWebView.map { Double($0.pageZoom) } ?? 1 }

    func isPinned(for context: WKWebExtensionContext) -> Bool { isPinned }

    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext) async throws {
        guard pinned != isPinned, let browser else { return }
        let destination = pinned
            ? TabPosition(section: .pinned, index: browser.pinnedTabs.count)
            : TabPosition(section: .today, index: 0)
        browser.moveTab(self, to: destination)
    }

    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool { isPlayingAudio }

    func isMuted(for context: WKWebExtensionContext) -> Bool { isMuted }

    func setMuted(_ muted: Bool, for context: WKWebExtensionContext) async throws {
        if muted != isMuted { toggleMuted() }
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool { browser?.activeTab === self }

    func activate(for context: WKWebExtensionContext) async throws { browser?.select(self) }

    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws { load(url) }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws { reload(ignoringCache: fromOrigin) }

    func goBack(for context: WKWebExtensionContext) async throws { goBack() }

    func goForward(for context: WKWebExtensionContext) async throws { goForward() }

    func close(for context: WKWebExtensionContext) async throws { browser?.close(self) }

    func snapshot(using configuration: WKSnapshotConfiguration, for context: WKWebExtensionContext) async throws -> NSImage? {
        try await loadedWebView?.takeSnapshot(configuration: configuration)
    }
}

/// Pulse has one window per browser; extensions see every space's tabs in it, favorites first.
extension Browser: WKWebExtensionWindow {
    /// A stable order, unlike `everyTab`, which changes with the active space.
    var extensionTabs: [Tab] { tabsInAllProfiles }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { extensionTabs }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { activeTab }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        if window.isMiniaturized { return .minimized }
        return window.isZoomed ? .maximized : .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { isPrivate }

    func frame(for context: WKWebExtensionContext) -> CGRect { window?.frame ?? .null }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect { window?.screen?.frame ?? .null }

    func focus(for context: WKWebExtensionContext) async throws { window?.makeKeyAndOrderFront(nil) }
}
