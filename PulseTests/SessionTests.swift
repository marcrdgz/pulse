import Foundation
import Testing
@testable import Pulse

struct SessionTests {
    private let store = SessionStore(
        fileURL: FileManager.default.temporaryDirectory
            .appending(path: "PulseTests-\(UUID().uuidString)")
            .appending(path: "session.json")
    )

    @Test func restoresTabsPinsAndSelection() throws {
        let browser = Browser(sessionStore: store)
        browser.openTab(url: URL(string: "https://a.com")!)
        browser.openTab(url: URL(string: "https://b.com")!)
        browser.openTab(url: URL(string: "https://c.com")!)
        browser.togglePin(browser.todayTabs[2])
        browser.select(browser.todayTabs[1])
        browser.rename(browser.todayTabs[0], to: "Renamed")
        browser.saveSession()

        let restored = Browser(sessionStore: store)
        #expect(restored.session == browser.session)
        #expect(restored.activeTab?.url == URL(string: "https://b.com")!)
        #expect(restored.pinnedTabs.first?.pinnedURL == URL(string: "https://a.com")!)
        #expect(restored.commandBar == nil)
        #expect(restored.todayTabs.first?.displayTitle == "Renamed")

        try FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }

    @Test func fallsBackToFirstTabWhenActiveTabIsMissing() throws {
        let tab = Session.SavedTab(id: UUID(), url: URL(string: "https://a.com")!, title: "A")
        try store.save(Session(pinnedTabs: [], todayTabs: [tab], activeTabID: UUID()))

        #expect(Browser(sessionStore: store).activeTabID == tab.id)

        try FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }
}
