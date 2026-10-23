import Foundation
import Testing
import WebKit
@testable import Pulse

struct ContentBlockerTests {
    private let page = "<div class='ad-banner'>Ad</div>"
    private let site = URL(string: "https://example.com")!

    @Test func hidesAdsUnlessTheSiteIsAllowed() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try #require(WKContentRuleListStore(url: directory))
        let encoded = try FilterList.encodedRuleLists(from: ["##.ad-banner"])
        _ = try await store.compileContentRuleList(forIdentifier: "ads", encodedContentRuleList: encoded[0])

        // As a previous launch leaves them, so nothing is downloaded.
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        defaults.set(["ads"], forKey: "contentBlockerIdentifiers")
        defaults.set(Date.now, forKey: "contentBlockerLastUpdate")
        let preferences = Preferences()
        let blocker = ContentBlocker(store: store, defaults: defaults, preferences: preferences)
        let browser = Browser(contentBlocker: blocker, preferences: preferences)
        try await waitUntil { !blocker.ruleLists.isEmpty }

        let tab = browser.openTab(url: URL(string: "about:blank")!)
        tab.webView.loadHTMLString(page, baseURL: site)
        try await waitUntil { await display(in: tab) == "none" }

        browser.toggleContentBlocking(on: tab)
        #expect(preferences.adsAllowedSites == ["example.com"])
        tab.webView.loadHTMLString(page, baseURL: site)
        try await waitUntil { await display(in: tab) == "block" }
    }

    private func display(in tab: Tab) async -> String? {
        try? await tab.webView.evaluateJavaScript(
            "getComputedStyle(document.querySelector('.ad-banner')).display"
        ) as? String
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        var isMet = await condition()
        for _ in 0..<100 where !isMet {
            try await Task.sleep(for: .milliseconds(50))
            isMet = await condition()
        }
        #expect(isMet)
    }
}
