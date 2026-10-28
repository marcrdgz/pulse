import Foundation
import Testing
import WebKit
@testable import Pulse

struct PrivateBrowserTests {
    private let site = URL(string: "https://example.com")!

    @Test func privateWindowsKeepTheirStorageToThemselves() async throws {
        let main = Browser()
        let first = Browser.makePrivate(contentBlocker: main.contentBlocker, preferences: main.preferences)
        let second = Browser.makePrivate(contentBlocker: main.contentBlocker, preferences: main.preferences)
        #expect(first.isPrivate && first.activeSpace.name == "Private")
        let firstStore = first.dataStore(for: Profile.defaultID)
        #expect(!firstStore.isPersistent)
        #expect(firstStore !== second.dataStore(for: Profile.defaultID))

        let privateTab = first.openTab(url: URL(string: "about:blank")!)
        privateTab.webView.loadHTMLString("<title>Ready</title>", baseURL: site)
        try await waitUntil { privateTab.title == "Ready" }
        #expect(privateTab.webView.configuration.websiteDataStore === firstStore)
        _ = try await privateTab.webView.evaluateJavaScript("localStorage.setItem('secret', '1'); 0")

        let otherTab = second.openTab(url: URL(string: "about:blank")!)
        otherTab.webView.loadHTMLString("<title>Ready</title>", baseURL: site)
        try await waitUntil { otherTab.title == "Ready" }
        let leaked = try await otherTab.webView.evaluateJavaScript("localStorage.getItem('secret')")
        #expect(leaked == nil || leaked is NSNull)
    }

    @Test func allowingAdsOnASiteReachesEveryWindow() {
        let preferences = Preferences()
        let main = Browser(contentBlocker: ContentBlocker(preferences: preferences), preferences: preferences)
        let privateBrowser = Browser.makePrivate(contentBlocker: main.contentBlocker, preferences: main.preferences)
        let tab = privateBrowser.openTab(url: site)

        privateBrowser.toggleContentBlocking(on: tab)
        #expect(!main.contentBlocker.isBlocking(on: site))
        #expect(main.preferences.adsAllowedSites == ["example.com"])
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition())
    }
}
