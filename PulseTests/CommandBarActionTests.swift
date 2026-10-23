import Foundation
import Testing
@testable import Pulse

struct CommandBarActionTests {
    private func suggestions(_ text: String, in browser: Browser) -> [OmniboxSuggestion] {
        Omnibox.result(
            for: text,
            history: [],
            openTabs: browser.everyTab,
            searchSuggestions: [],
            actions: browser.commandBarActions,
            allowsInlineCompletion: true
        ).suggestions
    }

    private func titles(_ suggestions: [OmniboxSuggestion]) -> [String] {
        suggestions.compactMap { if case .action(let action) = $0 { action.title } else { nil } }
    }

    @Test func matchingActionsFollowWhatWasTyped() {
        let browser = Browser()
        browser.openTab(url: URL(string: "https://example.com")!)

        let results = suggestions("pin", in: browser)
        #expect(results.first?.id == "search:pin")
        #expect(titles(results) == ["Pin Tab"])
        #expect(titles(suggestions("cl ot", in: browser)) == ["Close Other Tabs"])
        #expect(titles(suggestions("devtools", in: browser)) == ["Show Web Inspector"])
    }

    @Test func tabActionsNeedATab() {
        let browser = Browser()
        #expect(titles(suggestions("copy", in: browser)).isEmpty)
        #expect(titles(suggestions("history", in: browser)) == ["Show History"])
    }

    @Test func movesTheTabToAnotherSpace() throws {
        let browser = Browser()
        let home = browser.activeSpace
        let work = browser.createSpace()
        browser.rename(work, to: "Work")
        browser.selectSpace(home)
        let tab = browser.openTab(url: URL(string: "https://example.com")!)
        browser.showCommandBar(.newTab)

        let move = try #require(browser.commandBarActions.first { $0.title == "Move Tab to Work" })
        browser.perform(move.kind)
        #expect(browser.activeSpace === work)
        #expect(work.todayTabs.first === tab)
        #expect(browser.commandBar == nil)
    }

    @Test func titlesFollowTheTabsState() throws {
        let browser = Browser()
        let tab = browser.openTab(url: URL(string: "https://example.com")!)
        browser.perform(.togglePin)
        #expect(tab.isPinned)
        #expect(browser.commandBarActions.contains { $0.title == "Unpin Tab" })
        #expect(browser.commandBarActions.contains { $0.title == "Allow Ads on example.com" })
    }
}
