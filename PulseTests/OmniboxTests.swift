import Foundation
import Testing
@testable import Pulse

struct OmniboxTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ url: String, title: String = "", visits: Int = 1, typed: Int = 0, daysAgo: Double = 0) -> HistoryEntry {
        HistoryEntry(
            url: URL(string: url)!,
            title: title,
            visitCount: visits,
            typedCount: typed,
            lastVisit: now.addingTimeInterval(-daysAgo * 86_400)
        )
    }

    private func result(_ text: String, _ history: [HistoryEntry], tabs: [Tab] = [], search: [String] = [], inline: Bool = true) -> OmniboxResult {
        Omnibox.result(for: text, history: history, openTabs: tabs, searchSuggestions: search, allowsInlineCompletion: inline, now: now)
    }

    @Test func completesTheHostOfAFrequentSiteKeepingTheTypedCase() {
        let result = result("GiT", [entry("https://github.com/apple/swift", title: "Swift", typed: 1)])

        #expect(result.inlineCompletion == "GiThub.com")
        #expect(result.suggestions.first?.fillText == "https://github.com/")
        #expect(result.suggestions.contains { $0.id == "search:GiT" })
    }

    @Test func completesTheFullAddressOnceAPathIsTyped() {
        let result = result("github.com/ap", [entry("https://github.com/apple", visits: 3)])
        #expect(result.inlineCompletion == "github.com/apple")
    }

    @Test func doesntCompleteRareSitesOrAfterDeleting() {
        let once = [entry("https://github.com/", visits: 1)]
        #expect(result("git", once).inlineCompletion == nil)

        let frequent = [entry("https://github.com/", visits: 5)]
        #expect(result("git", frequent, inline: false).inlineCompletion == nil)
        #expect(result("git hub", frequent).inlineCompletion == nil)
    }

    @Test func typedAndRecentSitesRankFirst() {
        let history = [
            entry("https://docs.old.com/", title: "Docs", visits: 30, daysAgo: 60),
            entry("https://docs.typed.com/", title: "Docs", visits: 2, typed: 3),
            entry("https://docs.recent.com/", title: "Docs", visits: 10),
        ]
        let urls = result("docs", history, inline: false).suggestions.compactMap { suggestion -> String? in
            if case .navigate(let url, let title) = suggestion, title != nil { return url.host() }
            return nil
        }
        #expect(urls == ["docs.typed.com", "docs.recent.com", "docs.old.com"])
    }

    @Test func openPagesBecomeSwitchToTab() {
        let tab = Tab(url: URL(string: "https://news.ycombinator.com/")!, title: "Hacker News")
        let result = result("news", [entry("https://news.ycombinator.com/", title: "Hacker News")], tabs: [tab])

        #expect(result.suggestions.contains { $0.id == "tab:\(tab.id)" })
        #expect(!result.suggestions.contains { $0.id == "url:https://news.ycombinator.com/" })
    }

    @Test func appendsSearchSuggestionsWithoutDuplicatesAndCapsTheList() {
        let search = ["swift", "swift concurrency", "swift ui", "swift testing", "swift 6", "swiftly", "swift charts"]
        let history = (1...6).map { entry("https://swift\($0).org/", title: "Swift \($0)") }
        let suggestions = result("swift", history, search: search, inline: false).suggestions

        #expect(suggestions.count == Omnibox.maxSuggestions)
        #expect(suggestions.filter { $0.id == "search:swift" }.count == 1)
    }

    @Test func emptyInputListsOpenTabs() {
        let tabs = [Tab(url: URL(string: "https://a.com")!), Tab(url: URL(string: "https://b.com")!)]
        #expect(result("", [], tabs: tabs).suggestions.map(\.id) == tabs.map { "tab:\($0.id)" })
    }
}
