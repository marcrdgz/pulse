import AppKit
import Observation
import WebKit

@Observable
final class Tab: NSObject, Identifiable {
    let id: UUID
    private(set) var url: URL
    private(set) var title: String
    private(set) var favicon: NSImage?
    private(set) var isLoading = false
    private(set) var estimatedProgress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var loadError: LoadError?
    /// The URL of the link under the pointer, previewed at the bottom of the page.
    private(set) var hoveredLink: String?
    private(set) var cameraCaptureState: WKMediaCaptureState = .none
    private(set) var microphoneCaptureState: WKMediaCaptureState = .none
    /// Asleep to free memory; showing the tab brings the page back where it was.
    private(set) var isHibernated = false
    /// The page is making sound (or would be, if muted).
    private(set) var isPlayingAudio = false
    /// Silences the page, even across sleeping and reloads, until unmuted.
    private(set) var isMuted = false
    /// The page a pinned tab returns to when closed; `nil` for today tabs.
    var pinnedURL: URL?
    /// Set by the user from the sidebar; overrides the page title.
    var customTitle: String?

    @ObservationIgnored weak var browser: Browser?
    /// The tab whose page opened this one with `window.open` or `target=_blank`.
    @ObservationIgnored weak var opener: Tab?
    @ObservationIgnored private(set) var loadedWebView: WKWebView?
    @ObservationIgnored private var coordinator: WebViewCoordinator?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var appliedRuleListIDs: [String] = []
    @ObservationIgnored private var audioObservation: NSObject?
    /// The back/forward list and scroll position saved when the tab went to sleep.
    @ObservationIgnored private var hibernatedState: Any?
    /// Pages opened by script keep a live `window.opener` (sign-in popups), which a reload would cut.
    @ObservationIgnored private var isOpenedByScript = false
    /// When the tab was last on screen; inactive tabs go to sleep after a while.
    @ObservationIgnored private(set) var lastShown = Date.now

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
        super.init()
    }

    var isPinned: Bool { pinnedURL != nil }

    var internalPage: InternalPage? { InternalPage(url: url) }

    /// e.g. "Using camera and microphone" or "Muted"; `nil` while the page captures and plays nothing.
    var mediaDescription: String? {
        let devices = [(cameraCaptureState, "camera"), (microphoneCaptureState, "microphone")]
        let active = devices.filter { $0.0 == .active }.map(\.1)
        let muted = devices.filter { $0.0 == .muted }.map(\.1)
        if !active.isEmpty { return "Using " + active.joined(separator: " and ") }
        if !muted.isEmpty { return "Paused " + muted.joined(separator: " and ") }
        if isMuted { return "Muted" }
        if isPlayingAudio { return "Playing audio" }
        return nil
    }

    func toggleMuted() {
        isMuted.toggle()
        if let loadedWebView { PageAudio.setMuted(isMuted, in: loadedWebView) }
        browser?.extensions?.controller.didChangeTabProperties(.muted, for: self)
    }

    var displayTitle: String {
        customTitle ?? internalPage?.title ?? (title.isEmpty ? (url.displayHost ?? "New Tab") : title)
    }

    /// Created on first access so restored, background and sleeping tabs cost nothing until shown.
    var webView: WKWebView {
        if let loadedWebView { return loadedWebView }
        let webView = attach(BrowserWebView(frame: .zero, configuration: makeConfiguration()))
        if let hibernatedState {
            webView.interactionState = hibernatedState
        } else {
            webView.load(URLRequest(url: url))
        }
        hibernatedState = nil
        isHibernated = false
        lastShown = .now
        return webView
    }

    /// Hosts a web view WebKit asked for (`window.open`, `target=_blank`); WebKit drives its loading.
    func adoptWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        isOpenedByScript = true
        return attach(BrowserWebView(frame: .zero, configuration: configuration))
    }

    func wasShown(at date: Date) {
        lastShown = date
    }

    /// Whether the page can sleep without the user losing anything: it isn't playing media,
    /// using the camera or microphone, or talking to the page that opened it.
    func canHibernate() async -> Bool {
        guard let loadedWebView, !isOpenedByScript, cameraCaptureState == .none, microphoneCaptureState == .none
        else { return false }
        return await loadedWebView.requestMediaPlaybackState() != .playing
    }

    /// Frees the web view, keeping its back/forward list so showing the tab restores the page.
    func hibernate() {
        guard let loadedWebView else { return }
        let state = loadedWebView.interactionState
        unload()
        hibernatedState = state
        isHibernated = true
    }

    func load(_ url: URL) {
        loadError = nil
        if let page = InternalPage(url: url) {
            // Internal pages are drawn by Pulse; the web view comes back when navigating away.
            unload()
            self.url = page.url
            title = ""
        } else {
            self.url = url
            // A sleeping tab wakes up on the new page rather than the one it slept on.
            hibernatedState = nil
            isHibernated = false
            loadedWebView?.load(URLRequest(url: url))
        }
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
        // A popup opened just for the download (a `target=_blank` link to a file) has nothing to show.
        if opener != nil, loadedWebView?.backForwardList.currentItem == nil {
            browser?.close(self)
            return
        }
        guard let currentURL = loadedWebView?.backForwardList.currentItem?.url, currentURL != url else { return }
        url = currentURL
        browser?.tabDidUpdate()
    }

    func navigationDidStart() {
        loadError = nil
        hoveredLink = nil
    }

    func hoveredLinkDidChange(to link: String?) {
        hoveredLink = link
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

    /// Pages load with the content blocker's rules unless the user allowed ads on their site.
    /// Called before each main-frame navigation, since the rules depend on the page's site.
    func applyContentRules(forPageAt pageURL: URL) {
        guard let controller = loadedWebView?.configuration.userContentController else { return }
        let lists = browser?.contentBlocker.rules(forPageAt: pageURL) ?? []
        let identifiers = lists.compactMap(\.identifier)
        guard identifiers != appliedRuleListIDs else { return }
        controller.removeAllContentRuleLists()
        lists.forEach(controller.add)
        appliedRuleListIDs = identifiers
    }

    /// Drops the web view (and its process memory); the tab reloads lazily when shown again.
    func unload() {
        observations.removeAll()
        audioObservation = nil
        isPlayingAudio = false
        appliedRuleListIDs = []
        hibernatedState = nil
        isHibernated = false
        loadedWebView?.stopLoading()
        loadedWebView?.removeFromSuperview()
        loadedWebView = nil
        coordinator = nil
        loadError = nil
        hoveredLink = nil
        isLoading = false
        estimatedProgress = 0
        cameraCaptureState = .none
        microphoneCaptureState = .none
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
        let loader = browser?.faviconLoader ?? .shared
        Task { [weak self] in
            guard let icon = await loader.favicon(forPage: pageURL, declaredIconURL: declaredIconURL) else { return }
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
        applyContentRules(forPageAt: url)
        if isMuted { PageAudio.setMuted(true, in: webView) }
        audioObservation = PageAudio.observe(webView) { [weak self] isPlaying in self?.audioDidChange(isPlaying: isPlaying) }

        observations = [
            webView.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.isLoading) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.estimatedProgress) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.canGoForward) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.cameraCaptureState) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
            webView.observe(\.microphoneCaptureState) { [weak self] _, _ in MainActor.assumeIsolated { self?.syncWithWebView() } },
        ]
        return webView
    }

    private func audioDidChange(isPlaying: Bool) {
        guard isPlaying != isPlayingAudio else { return }
        isPlayingAudio = isPlaying
        browser?.extensions?.controller.didChangeTabProperties(.playingAudio, for: self)
    }

    private func syncWithWebView() {
        guard let webView = loadedWebView else { return }
        var didChangePage = false
        var changes: WKWebExtension.TabChangedProperties = []
        if let newURL = webView.url, newURL != url {
            url = newURL
            didChangePage = true
            changes.insert(.URL)
            // Same-document navigations (pushState) never commit, but Chrome still records them.
            if !webView.isLoading { browser?.recordVisit(to: self, title: webView.title ?? "") }
        }
        if let newTitle = webView.title, newTitle != title {
            title = newTitle
            didChangePage = true
            changes.insert(.title)
            browser?.tabTitleDidChange(self)
        }
        if webView.isLoading != isLoading { changes.insert(.loading) }
        isLoading = webView.isLoading
        estimatedProgress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        cameraCaptureState = webView.cameraCaptureState
        microphoneCaptureState = webView.microphoneCaptureState
        if didChangePage { browser?.tabDidUpdate() }
        if !changes.isEmpty { browser?.extensions?.controller.didChangeTabProperties(changes, for: self) }
    }

    private func setZoom(_ zoom: CGFloat) {
        loadedWebView?.pageZoom = min(max(zoom, 0.3), 3)
    }

    private func makeConfiguration() -> WKWebViewConfiguration {
        let extensions = browser?.extensions
        // An extension's own pages (its options, say) only load with the configuration WebKit made for them.
        let configuration = extensions?.webViewConfiguration(forPageAt: url) ?? WKWebViewConfiguration()
        configuration.webExtensionController = extensions?.controller
        configuration.websiteDataStore = browser?.websiteDataStore ?? .default()
        // Without a Safari token some sites (e.g. Google) serve degraded markup to WKWebView.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true
        LinkHover.install(in: configuration.userContentController)
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
