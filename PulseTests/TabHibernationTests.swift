import Foundation
import Testing
import WebKit
@testable import Pulse

struct TabHibernationTests {
    private func page(_ title: String) throws -> URL {
        let html = "<title>\(title)</title>"
        return try #require(URL(string: "data:text/html," + html.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!))
    }

    @Test func inactiveTabsSleepAndWakeUpWhereTheyWere() async throws {
        let browser = Browser()
        let tab = browser.openTab(url: try page("First"))
        _ = tab.webView
        try await waitUntil { tab.title == "First" }
        tab.load(try page("Second"))
        try await waitUntil { tab.title == "Second" && tab.canGoBack }
        let other = browser.openTab(url: try page("Other"))
        _ = other.webView

        await browser.hibernateInactiveTabs(now: .now + 30 * 60)
        #expect(!tab.isHibernated)

        await browser.hibernateInactiveTabs(now: .now + 2 * 60 * 60)
        #expect(tab.isHibernated)
        #expect(!other.isHibernated)
        #expect(tab.displayTitle == "Second")

        browser.select(tab)
        _ = tab.webView
        try await waitUntil { tab.title == "Second" && tab.canGoBack }
        #expect(!tab.isHibernated)
    }

    @Test func navigatingASleepingTabWakesItOnTheNewPage() async throws {
        let browser = Browser()
        let tab = browser.openTab(url: try page("First"))
        _ = tab.webView
        try await waitUntil { tab.title == "First" }
        browser.openTab(url: try page("Other"))
        await browser.hibernateInactiveTabs(now: .now + 2 * 60 * 60)

        tab.load(try page("Elsewhere"))
        _ = tab.webView
        try await waitUntil { tab.title == "Elsewhere" }
    }

    @Test func neverSleepsWhenTurnedOff() async throws {
        let preferences = Preferences()
        preferences.tabSleepDelay = .never
        let browser = Browser(preferences: preferences)
        let tab = browser.openTab(url: try page("First"))
        _ = tab.webView
        browser.openTab(url: try page("Other"))

        await browser.hibernateInactiveTabs(now: .now + 24 * 60 * 60)
        #expect(!tab.isHibernated)
    }

    @Test func popupsStayAwakeForTheirOpener() async throws {
        let browser = Browser()
        let opener = browser.openTab(url: try page("Opener"))
        let popupView = browser.openPopup(from: opener, configuration: WKWebViewConfiguration())
        let popup = try #require(browser.todayTabs.first { $0.webView === popupView })
        browser.select(opener)

        await browser.hibernateInactiveTabs(now: .now + 2 * 60 * 60)
        #expect(!popup.isHibernated)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition())
    }
}
