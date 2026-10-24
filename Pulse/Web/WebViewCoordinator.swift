import AppKit
import WebKit

/// Navigation and UI delegate for a single tab's web view.
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private(set) weak var tab: Tab?
    /// Set by a context menu item just before WebKit asks for the window it opens.
    var pendingContextMenuOpen: ContextMenuOpen?
    /// JavaScript dialogs shown since the page committed; from the second on, each offers to
    /// silence the page, like Safari, so a dialog loop can't trap the window.
    private var dialogCount = 0
    private var suppressesDialogs = false

    init(tab: Tab) {
        self.tab = tab
    }

    func hoveredLinkDidChange(to link: String?) {
        tab?.hoveredLinkDidChange(to: link)
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if let url = navigationAction.request.url, url.opensInOtherApp {
            decisionHandler(.cancel)
            // A clicked link is consent enough; redirects and scripts must ask, like Safari.
            openInOtherApp(url, askFirst: navigationAction.navigationType != .linkActivated, from: webView.url)
            return
        }
        if openInPeek(navigationAction) {
            decisionHandler(.cancel)
            return
        }
        if case .newTab(let activate) = LinkTarget(navigationAction), let url = navigationAction.request.url {
            tab?.browser?.openTab(url: url, activate: activate).opener = tab
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url {
            tab?.applyContentRules(forPageAt: url)
            tab?.applyUserAgent(forPageAt: url)
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        respondTo challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let passwordMethods = [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest]
        guard passwordMethods.contains(challenge.protectionSpace.authenticationMethod),
              let credential = askForCredential(challenge)
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, credential)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        // Subframes count too: download pages often start the file from a hidden iframe.
        let isAttachment = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .lowercased().hasPrefix("attachment") ?? false
        decisionHandler(navigationResponse.canShowMIMEType && !isAttachment ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        tab?.browser?.downloads.track(download)
        tab?.navigationDidBecomeDownload()
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        tab?.browser?.downloads.track(download)
        tab?.navigationDidBecomeDownload()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tab?.navigationDidStart()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        tab?.navigationDidFail(with: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        tab?.navigationDidFail(with: error)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        dialogCount = 0
        suppressesDialogs = false
        guard let tab else { return }
        tab.browser?.recordVisit(to: tab)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab?.pageDidFinishLoading()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let tab, let browser = tab.browser else { return nil }
        if let url = navigationAction.request.url, openForContextMenu(url) {
            return nil
        }
        if openInPeek(navigationAction) {
            return nil
        }
        if case .newTab(let activate) = LinkTarget(navigationAction), let url = navigationAction.request.url {
            browser.openTab(url: url, activate: activate).opener = tab
            return nil
        }
        return browser.openPopup(from: tab, configuration: configuration)
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        // Like Chrome, an embedded frame asks on behalf of the page's site, which the prompt names
        // and the decision is remembered under: a grant to meet.google.com never extends to pages
        // embedding it. The back-forward item is the committed page; `url` may already name one
        // still loading.
        let site = frame.isMainFrame ? origin.displayName : webView.backForwardList.currentItem?.url.permissionOrigin
        guard let tab, let browser = tab.browser, let site else {
            decisionHandler(.deny)
            return
        }
        browser.requestPermission(
            from: tab,
            origin: site,
            kinds: PermissionKind.kinds(for: type),
            respond: decisionHandler
        )
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let tab { tab.browser?.close(tab) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        _ = await present(makeAlert(message: message, frame: frame), in: webView)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        let alert = makeAlert(message: message, frame: frame)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return await present(alert, in: webView) == .alertFirstButtonReturn
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        let alert = makeAlert(message: prompt, frame: frame)
        let field = NSTextField(string: defaultText ?? "")
        field.frame.size.width = 260
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return await present(alert, in: webView) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo
    ) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        return panel.runModal() == .OK ? panel.urls : nil
    }

    /// Only clicks peek: a page opening a window by script (a sign-in popup) needs a real one.
    private func openInPeek(_ action: WKNavigationAction) -> Bool {
        guard action.navigationType == .linkActivated, let tab, let browser = tab.browser,
              let url = action.request.url
        else { return false }
        // No target frame means a new window (`target=_blank`), which leaves the page too.
        let leavesPage = action.targetFrame?.isMainFrame ?? true
        guard browser.opensInPeek(url, clickedIn: tab, target: LinkTarget(action), leavesPage: leavesPage)
        else { return false }
        browser.openPeek(url, from: tab)
        return true
    }

    private func openInOtherApp(_ url: URL, askFirst: Bool, from pageURL: URL?) {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            NSSound.beep()
            return
        }
        if askFirst {
            let alert = NSAlert()
            alert.messageText = "Open “\(FileManager.default.displayName(atPath: app.path))”?"
            alert.informativeText = "\(pageURL?.displayHost ?? "This page") wants to open this application."
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        NSWorkspace.shared.open(url)
    }

    /// Basic and Digest auth sign-in, like Safari's sheet; `nil` when cancelled.
    private func askForCredential(_ challenge: URLAuthenticationChallenge) -> URLCredential? {
        let space = challenge.protectionSpace
        let alert = NSAlert()
        alert.messageText = "Log in to \(space.host)"
        alert.informativeText = space.receivesCredentialSecurely
            ? "Your login information will be sent securely."
            : "Your login information will be sent unencrypted."
        let user = NSTextField(string: challenge.proposedCredential?.user ?? "")
        user.placeholderString = "Username"
        let password = NSSecureTextField(string: "")
        password.placeholderString = "Password"
        let fields = NSStackView(views: [user, password])
        fields.orientation = .vertical
        fields.frame.size = NSSize(width: 260, height: 52)
        user.nextKeyView = password
        alert.accessoryView = fields
        alert.addButton(withTitle: "Log In")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = user.stringValue.isEmpty ? user : password
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return URLCredential(user: user.stringValue, password: password.stringValue, persistence: .forSession)
    }

    /// A sheet on the page's window rather than an app-modal alert, so other windows stay usable.
    /// `nil` when the page has been silenced or has no window to show it in.
    private func present(_ alert: NSAlert, in webView: WKWebView) async -> NSApplication.ModalResponse? {
        guard !suppressesDialogs, let window = webView.window ?? tab?.browser?.window else { return nil }
        dialogCount += 1
        if dialogCount > 1 {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Prevent this page from creating additional dialogs"
        }
        let response = await alert.beginSheetModal(for: window)
        if alert.suppressionButton?.state == .on { suppressesDialogs = true }
        return response
    }

    private func makeAlert(message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.displayHost ?? "This page says"
        alert.informativeText = message
        return alert
    }
}

private extension LinkTarget {
    init(_ action: WKNavigationAction) {
        self.init(
            isLinkClick: action.navigationType == .linkActivated,
            buttonMask: action.buttonNumber,
            modifierFlags: action.modifierFlags
        )
    }
}
