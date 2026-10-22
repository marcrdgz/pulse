import AppKit
import Observation
import WebKit

@Observable
final class Tab: Identifiable {
    let id: UUID
    private(set) var url: URL
    private(set) var title: String
    private(set) var favicon: NSImage?
    private(set) var isLoading = false
    private(set) var estimatedProgress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var loadError: LoadError?
    /// The page a pinned tab returns to when closed; `nil` for today tabs.
    var pinnedURL: URL?
    /// Set by the user from the sidebar; overrides the page title.
    var customTitle: String?

    @ObservationIgnored weak var browser: Browser?
    @ObservationIgnored private var loadedWebView: WKWebView?
    @ObservationIgnored private var coordinator: WebViewCoordinator?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    struct LoadError: Equatable {
        let url: URL
        let code: Int
        let message: String

        var isOffline: Bool { code == NSURLErrorNotConnectedToInternet }
    }

    init(id: UUID = UUID(), url: URL, title: String = "", pinnedURL: URL? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.pinnedURL = pinnedURL
    }

    var isPinned: Bool { pinnedURL != nil }

    var displayTitle: String {
        customTitle ?? (title.isEmpty ? (url.displayHost ?? "New Tab") : title)
    }

    /// Created on first access so restored and background tabs cost nothing until shown.
    var webView: WKWebView {
        if let loadedWebView { return loadedWebView }
        let webView = attach(WKWebView(frame: .zero, configuration: Self.makeConfiguration()))
        webView.load(URLRequest(url: url))
        return webView
    }

    /// Hosts a web view WebKit asked for (`window.open`, `target=_blank`); WebKit drives its loading.
    func adoptWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        attach(WKWebView(frame: .zero, configuration: configuration))
    }

    func load(_ url: URL) {
        self.url = url
        loadError = nil
        loadedWebView?.load(URLRequest(url: url))
        browser?.tabDidUpdate()
    }

    func goBack() { loadedWebView?.goBack() }
    func goForward() { loadedWebView?.goForward() }
    func stopLoading() { loadedWebView?.stopLoading() }

    func reload(ignoringCache: Bool = false) {
        if let loadError {
            load(loadError.url)
        } else if ignoringCache {
            loadedWebView?.reloadFromOrigin()
        } else {
            loadedWebView?.reload()
        }
    }

    func zoomIn() { setZoom((loadedWebView?.pageZoom ?? 1) + 0.1) }
    func zoomOut() { setZoom((loadedWebView?.pageZoom ?? 1) - 0.1) }
    func resetZoom() { setZoom(1) }

    /// Highlights and scrolls to the next match; returns whether the page contains `query`.
    func find(_ query: String, backwards: Bool) async -> Bool {
        guard let loadedWebView else { return false }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        return (try? await loadedWebView.find(query, configuration: configuration))?.matchFound ?? false
    }

    func clearFindSelection() {
        loadedWebView?.evaluateJavaScript("window.getSelection().removeAllRanges()")
    }

    /// WebKit leaves `url` pointing at the file after a navigation becomes a download;
    /// the page actually shown is the current history item.
    func navigationDidBecomeDownload() {
        guard let currentURL = loadedWebView?.backForwardList.currentItem?.url, currentURL != url else { return }
        url = currentURL
        browser?.tabDidUpdate()
    }

    func navigationDidStart() {
        loadError = nil
    }

    func navigationDidFail(with error: Error) {
        let error = error as NSError
        // Cancelled loads and responses turned into downloads (WebKit 102) aren't page failures.
        let isInterruption = (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && error.code == 102)
        guard !isInterruption else { return }
        loadError = LoadError(
            url: error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? url,
            code: error.code,
            message: error.localizedDescription
        )
    }

    func showWebInspector() {
        // WebKit has no public API to open the inspector; `_inspector` is the SPI other WebKit shells use.
        let selector = NSSelectorFromString("_inspector")
        guard let webView = loadedWebView, webView.responds(to: selector),
              let inspector = webView.perform(selector)?.takeUnretainedValue() as? NSObject
        else { return }
        inspector.perform(NSSelectorFromString("show"))
    }

    /// Drops the web view (and its process memory); the tab reloads lazily when shown again.
    func unload() {
        observations.removeAll()
        loadedWebView?.stopLoading()
        loadedWebView?.removeFromSuperview()
        loadedWebView = nil
        coordinator = nil
        loadError = nil
        isLoading = false
        estimatedProgress = 0
        canGoBack = false
        canGoForward = false
    }

    func resetToPinnedURL() {
        guard let pinnedURL else { return }
        unload()
        url = pinnedURL
        title = ""
    }

    func pageDidFinishLoading() {
        loadedWebView?.evaluateJavaScript(FaviconLoader.declaredIconScript) { [weak self] result, _ in
            self?.loadFavicon(declaredIconURL: (result as? String).flatMap(URL.init(string:)))
        }
    }

    /// Without a loaded page only the site's `/favicon.ico` is known; used for restored, not-yet-shown tabs.
    func loadFavicon(declaredIconURL: URL? = nil) {
        let pageURL = url
        Task { [weak self] in
            guard let icon = await FaviconLoader.shared.favicon(forPage: pageURL, declaredIconURL: declaredIconURL)
            else { return }
            self?.favicon = icon
        }
    }

    private func attach(_ webView: WKWebView) -> WKWebView {
        let coordinator = WebViewCoordinator(tab: self)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        self.coordinator = coordinator
        loadedWebView = webView

        observations = [
            webView.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.isLoading) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.estimatedProgress) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.canGoForward) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
        ]
        return webView
    }

    private func syncWithWebView() {
        guard let webView = loadedWebView else { return }
        var didChangePage = false
        if let newURL = webView.url, newURL != url {
            url = newURL
            didChangePage = true
        }
        if let newTitle = webView.title, newTitle != title {
            title = newTitle
            didChangePage = true
        }
        isLoading = webView.isLoading
        estimatedProgress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if didChangePage { browser?.tabDidUpdate() }
    }

    private func setZoom(_ zoom: CGFloat) {
        loadedWebView?.pageZoom = min(max(zoom, 0.3), 3)
    }

    private static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Without a Safari token some sites (e.g. Google) serve degraded markup to WKWebView.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true
        return configuration
    }
}

extension URL {
    /// The host as Arc shows it in the address pill: without `www.`.
    var displayHost: String? {
        guard let host = host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
