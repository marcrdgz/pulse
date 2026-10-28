import Foundation
import Testing
import WebKit
@testable import Pulse

struct ProfilesTests {
    private let a = URL(string: "https://a.com")!
    private let b = URL(string: "https://b.com")!
    private let store = SessionStore(
        fileURL: FileManager.default.temporaryDirectory
            .appending(path: "PulseTests-\(UUID().uuidString)")
            .appending(path: "session.json")
    )

    @Test func spacesInDifferentProfilesKeepSeparateDataAndFavorites() throws {
        let browser = Browser()
        let home = browser.activeSpace
        browser.toggleFavorite(browser.openTab(url: a))
        let work = browser.createSpace()
        let profile = try #require(browser.createProfile(named: " Work "))
        #expect(profile.name == "Work")

        browser.setProfile(profile.id, for: work)
        #expect(browser.favorites.isEmpty)
        let workTab = browser.openTab(url: b)
        browser.toggleFavorite(workTab)
        #expect(browser.favorites.map(\.url) == [b])
        #expect(browser.dataStore(for: workTab) === browser.dataStore(for: profile.id))
        #expect(browser.dataStore(for: workTab) !== WKWebsiteDataStore.default())
        #expect(browser.everyTab.allSatisfy { $0.url != a })

        browser.selectSpace(home)
        #expect(browser.favorites.map(\.url) == [a])
        #expect(browser.dataStore(for: browser.favorites[0]) === WKWebsiteDataStore.default())
        #expect(browser.tabsInAllProfiles.count == 2)
    }

    @Test func peekUsesItsOpenersProfile() throws {
        let browser = Browser()
        let profile = try #require(browser.createProfile(named: "Work"))
        browser.setProfile(profile.id, for: browser.activeSpace)
        let opener = browser.openTab(url: a)

        browser.openPeek(b, from: opener)
        let peek = try #require(browser.peek)
        #expect(browser.profileID(of: peek) == profile.id)
    }

    @Test func movingATabToAnotherProfileGivesItThatProfilesWebView() async throws {
        let browser = Browser()
        let home = browser.activeSpace
        let tab = browser.openTab(url: URL(string: "about:blank")!)
        #expect(tab.webView.configuration.websiteDataStore === WKWebsiteDataStore.default())
        let work = browser.createSpace()
        let profile = try #require(browser.createProfile(named: "Work"))
        browser.setProfile(profile.id, for: work)

        browser.moveTab(tab, to: work)
        #expect(tab.webView.configuration.websiteDataStore === browser.dataStore(for: profile.id))

        browser.selectSpace(home)
        browser.delete(profile)
        #expect(browser.profiles == [.default])
        #expect(work.profileID == Profile.defaultID)
        #expect(tab.webView.configuration.websiteDataStore === WKWebsiteDataStore.default())
        tab.unload()
    }

    @Test func deletingAProfileKeepsItsSpacesAndFavoritesInTheDefaultOne() throws {
        let browser = Browser()
        browser.toggleFavorite(browser.openTab(url: a))
        let work = browser.createSpace()
        let profile = try #require(browser.createProfile(named: "Work"))
        browser.setProfile(profile.id, for: work)
        browser.toggleFavorite(browser.openTab(url: b))

        browser.delete(profile)
        #expect(browser.activeSpace === work)
        #expect(browser.favorites.map(\.url) == [a, b])
        browser.delete(Profile.default)
        #expect(browser.profiles == [.default])
    }

    @Test func profilesAndTheirFavoritesAreRestored() throws {
        let browser = Browser(sessionStore: store)
        browser.toggleFavorite(browser.openTab(url: a))
        let work = browser.createSpace()
        let profile = try #require(browser.createProfile(named: "Work"))
        browser.setProfile(profile.id, for: work)
        browser.toggleFavorite(browser.openTab(url: b))
        browser.rename(profile, to: "Job")
        browser.saveSession()

        let restored = Browser(sessionStore: store)
        #expect(restored.session == browser.session)
        #expect(restored.profiles.map(\.name) == ["Default", "Job"])
        #expect(restored.activeSpace.profileID == profile.id)
        #expect(restored.favorites.map(\.url) == [b])
        #expect(restored.favorites(in: Profile.defaultID).map(\.url) == [a])

        try FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }

    @Test func spacesOfAnUnknownProfileFallBackToTheDefaultOne() throws {
        let space = Session.SavedSpace(
            id: UUID(), name: "Work", theme: "blue", pinnedTabs: [], todayTabs: [], activeTabID: nil,
            profileID: UUID()
        )
        try store.save(Session(favorites: [], spaces: [space], activeSpaceID: space.id))

        #expect(Browser(sessionStore: store).activeSpace.profileID == Profile.defaultID)

        try FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }
}
