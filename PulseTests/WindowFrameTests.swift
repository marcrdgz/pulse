import AppKit
import Testing
import WebKit
@testable import Pulse

/// Pages read their window through WebKit SPI that Safari implements; a stand-in page is served from the store, so nothing is downloaded.
struct WindowFrameTests {
    /// The store's bot check flags a page whose window reports no outer size as headless.
    @Test func pagesSeeTheirWindowsSize() async throws {
        let tab = Browser().openTab(url: URL(string: "about:blank")!)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = tab.webView
        try await load(URL(string: "https://secure7.store.apple.com/es/shop/signIn")!, in: tab)

        let size = try await tab.webView.evaluateJavaScript("[outerWidth, outerHeight]") as? [Int]
        #expect(size == [Int(window.frame.width), Int(window.frame.height)])
    }

    private func load(_ url: URL, in tab: Tab) async throws {
        tab.webView.loadHTMLString("<p>Page</p>", baseURL: url)
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            let state = try? await tab.webView.evaluateJavaScript("location.href + document.readyState") as? String
            if state == url.absoluteString + "complete" { return }
        }
    }

    private func userAgent(of tab: Tab) async throws -> String? {
        try await tab.webView.evaluateJavaScript("navigator.userAgent") as? String
    }
}
