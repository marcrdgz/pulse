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
        let space = Session.SavedSpace(
            id: UUID(), name: "Work", theme: "blue", pinnedTabs: [], todayTabs: [tab], activeTabID: UUID()
        )
        try store.save(Session(favorites: [], spaces: [space], activeSpaceID: space.id))

        #expect(Browser(sessionStore: store).activeTabID == tab.id)

        try FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }

    @Test func restoresSpacesThemesAndPerSpaceSelection() throws {
        let browser = Browser(sessionStore: store)
        browser.openTab(url: URL(string: "https://a.com")!)
        browser.toggleFavorite(browser.todayTabs[0])
        let work = browser.createSpace()
        browser.rename(work, to: "Work")
        browser.setTheme(.green, for: work)
        browser.openTab(url: URL(string: "https://b.com")!)
        browser.saveSession()

        let restored = Browser(sessionStore: store)
        #expect(restored.session == browser.session)
        #expect(restored.spaces.map(\.name) == ["Home", "Work"])
        #expect(restored.activeSpace.theme == .green)
        #expect(restored.activeTab?.url == URL(string: "https://b.com")!)
        #expect(restored.favorites.map(\.url) == [URL(string: "https://a.com")!])

        try FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }

    @Test func keepsAnUnreadableSessionInsteadOfOverwritingIt() throws {
        let directory = store.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.fileURL)

        let browser = Browser(sessionStore: store)
        browser.openTab(url: URL(string: "https://a.com")!)
        browser.saveSession()

        #expect(try Data(contentsOf: store.backupURL) == Data("{not json".utf8))
        #expect(store.load()?.spaces.first?.todayTabs.map(\.url) == [URL(string: "https://a.com")!])

        try FileManager.default.removeItem(at: directory)
    }

    /// Sessions saved before spaces: pinned tabs become favorites, the rest a single "Home" space.
    @Test func migratesSessionsFromBeforeSpaces() throws {
        let legacy = """
            {"pinnedTabs":[{"id":"11111111-1111-1111-1111-111111111111","url":"https://github.com",\
            "title":"GitHub","pinnedURL":"https://github.com"}],\
            "todayTabs":[{"id":"33333333-3333-3333-3333-333333333333","url":"https://swift.org","title":"Swift"}],\
            "activeTabID":"33333333-3333-3333-3333-333333333333"}
            """
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(legacy.utf8).write(to: store.fileURL)

        let browser = Browser(sessionStore: store)
        #expect(browser.favorites.map(\.url.host) == ["github.com"])
        #expect(browser.favorites.first?.isPinned == true)
        #expect(browser.spaces.map(\.name) == ["Home"])
        #expect(browser.todayTabs.map(\.url.host) == ["swift.org"])
        #expect(browser.activeTab?.url.host == "swift.org")

        try FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }
}
