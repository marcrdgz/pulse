import Foundation
import Testing
@testable import Pulse

struct HistoryStoreTests {
    private let history = HistoryStore(path: ":memory:")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let swift = URL(string: "https://swift.org/blog")!
    private let github = URL(string: "https://github.com/apple")!

    @Test func recordsVisitsNewestFirstAndCollapsesQuickRevisits() {
        history.recordVisit(url: swift, title: "Swift Blog", at: now)
        history.recordVisit(url: swift, title: "", at: now.addingTimeInterval(10))
        history.recordVisit(url: github, title: "Apple", at: now.addingTimeInterval(20))
        history.recordVisit(url: swift, title: "", at: now.addingTimeInterval(120))

        #expect(history.visits().map(\.url) == [swift, github, swift])
        #expect(history.visits().first?.title == "Swift Blog")
        let entry = history.entries(matching: "swift").first
        #expect(entry?.visitCount == 2)
        #expect(entry?.lastVisit == now.addingTimeInterval(120))
    }

    @Test func searchesEveryTermInURLOrTitle() {
        history.recordVisit(url: swift, title: "Swift Blog", at: now)
        history.recordVisit(url: github, title: "Apple", at: now)

        #expect(history.visits(matching: "apple").map(\.url) == [github])
        #expect(history.visits(matching: "swift blog").map(\.url) == [swift])
        #expect(history.visits(matching: "swift apple").isEmpty)
    }

    @Test func addressesTypedOftenStayCandidatesAmongNewerPages() {
        history.recordVisit(url: github, title: "Apple", at: now.addingTimeInterval(-10 * 86_400))
        (0..<5).forEach { _ in history.recordTyped(github) }
        for page in 0..<3 {
            history.recordVisit(url: URL(string: "https://example.com/\(page)")!, title: "", at: now)
        }

        #expect(history.entries(matching: "", limit: 3, now: now).map(\.url).contains(github) == false)
        #expect(history.entries(matching: "m", limit: 3, now: now).first?.url == github)
    }

    @Test func updatesTitlesAndCountsTypedAddresses() {
        history.recordVisit(url: swift, title: "", at: now)
        history.updateTitle("Swift.org", for: swift)
        history.recordTyped(swift)
        history.recordTyped(swift)

        let entry = history.entries(matching: "").first
        #expect(entry?.title == "Swift.org")
        #expect(entry?.typedCount == 2)
    }

    @Test func deletingVisitsKeepsCountersInStepAndDropsEmptyURLs() {
        history.recordVisit(url: swift, title: "Swift", at: now)
        history.recordVisit(url: swift, title: "Swift", at: now.addingTimeInterval(120))
        history.recordVisit(url: github, title: "GitHub", at: now)

        let latestSwiftVisit = history.visits(matching: "swift")[0]
        history.deleteVisits([latestSwiftVisit.id])
        #expect(history.entries(matching: "swift").first?.visitCount == 1)
        #expect(history.entries(matching: "swift").first?.lastVisit == now)

        history.deleteURL(github)
        #expect(history.entries(matching: "github").isEmpty)
        #expect(history.visits(matching: "github").isEmpty)
    }

    @Test func clearsByTimeRange() {
        history.recordVisit(url: swift, title: "Swift", at: now.addingTimeInterval(-7200))
        history.recordVisit(url: github, title: "GitHub", at: now)

        history.deleteVisits(since: now.addingTimeInterval(-3600))
        #expect(history.visits().map(\.url) == [swift])

        history.deleteVisits(since: nil)
        #expect(history.visits().isEmpty)
        #expect(history.entries(matching: "").isEmpty)
    }

    @Test func timeRangesMatchChrome() {
        #expect(BrowsingDataRange.lastHour.startDate(from: now) == now.addingTimeInterval(-3600))
        #expect(BrowsingDataRange.last4Weeks.startDate(from: now) == now.addingTimeInterval(-28 * 86_400))
        #expect(BrowsingDataRange.allTime.startDate(from: now) == nil)
    }
}

struct InternalPageTests {
    @Test func historyOpensAsItsOwnTabAndAcceptsChromeURLs() {
        let browser = Browser()
        browser.showHistory()
        #expect(browser.activeTab?.internalPage == .history)
        #expect(browser.activeTab?.displayTitle == "History")

        let tab = browser.openTab(url: URL(string: "https://a.com")!)
        tab.load(URL(string: "chrome://history")!)
        #expect(tab.url == URL(string: "pulse://history")!)

        tab.load(URL(string: "https://b.com")!)
        #expect(tab.internalPage == nil)
    }

    @Test func typedAddressesAreRecordedButInternalPagesAreNotVisits() {
        let history = HistoryStore(path: ":memory:")!
        let browser = Browser(history: history)

        browser.open(URL(string: "https://a.com")!, from: .newTab, isTyped: true)
        browser.showHistory()
        browser.recordVisit(to: browser.activeTab!)

        #expect(history.entries(matching: "").map(\.url) == [URL(string: "https://a.com")!])
        #expect(history.entries(matching: "").first?.typedCount == 1)
        #expect(history.visits().isEmpty)
    }

    @Test func recentlyClosedCanReopenAnyTab() {
        let browser = Browser()
        browser.openTab(url: URL(string: "https://a.com")!)
        browser.closeActiveTab()
        browser.openTab(url: URL(string: "https://b.com")!)
        browser.closeActiveTab()

        let closedA = browser.recentlyClosedTabs.last!
        browser.reopen(closedA)
        #expect(browser.activeTab?.url.host == "a.com")
        #expect(browser.recentlyClosedTabs.map(\.url.host) == ["b.com"])
    }
}
