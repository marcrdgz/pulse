import Foundation
import Testing
@testable import Pulse

struct LinkHoverTests {
    @Test func tracksTheLinkUnderThePointer() async throws {
        let html = "<title>Ready</title><a id='link' href='https://example.com/page'>Link</a>"
        let encoded = try #require(html.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))
        let tab = Tab(url: try #require(URL(string: "data:text/html," + encoded)))
        let webView = tab.webView
        try await waitUntil { tab.displayTitle == "Ready" }

        // Dispatched from the page's world; the hover script listens from its isolated one.
        _ = try await webView.evaluateJavaScript(
            "document.getElementById('link').dispatchEvent(new MouseEvent('mouseover', { bubbles: true })); 0"
        )
        try await waitUntil { tab.hoveredLink == "https://example.com/page" }

        _ = try await webView.evaluateJavaScript(
            "document.body.dispatchEvent(new MouseEvent('mouseout', { bubbles: true })); 0"
        )
        try await waitUntil { tab.hoveredLink == nil }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition())
    }
}
