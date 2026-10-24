import Foundation
import Testing
@testable import Pulse

struct ReleaseNotesTests {
    private func release(_ version: String, highlights: Bool = true) throws -> ReleaseNotes {
        let highlight = #"{"title": "Split View", "body": "Two tabs.", "symbol": "rectangle.split.2x1", "scene": "splitView"}"#
        let json = """
        [{"version": "\(version)", "date": "2026-10-23", "summary": "Things.",
          "highlights": [\(highlights ? highlight : "")], "improvements": [], "fixes": []}]
        """
        return try ReleaseNotes.decode(Data(json.utf8))[0]
    }

    private func browser(lastSeenVersion: String?, hasCompletedOnboarding: Bool = true) -> Browser {
        let preferences = Preferences()
        preferences.hasCompletedOnboarding = hasCompletedOnboarding
        preferences.lastSeenVersion = lastSeenVersion
        return Browser(preferences: preferences)
    }

    /// `/release` drafts this file, so mistakes must fail here rather than empty the page.
    @Test func bundledNotesDecodeNewestFirst() throws {
        let url = try #require(Bundle.main.url(forResource: "ReleaseNotes", withExtension: "json"))
        let releases = try ReleaseNotes.decode(Data(contentsOf: url))
        let versions = releases.map(\.version)
        #expect(versions == versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending })
        #expect(Set(versions).count == versions.count)
    }

    @Test func updateOpensWhatsNewOnce() throws {
        let browser = browser(lastSeenVersion: "0.2.0")
        browser.announceUpdate(to: "0.3.0", releases: [try release("0.3.0")])
        #expect(browser.activeTab?.internalPage == .whatsNew)
        #expect(browser.preferences.lastSeenVersion == "0.3.0")

        browser.closeActiveTab()
        browser.announceUpdate(to: "0.3.0", releases: [try release("0.3.0")])
        #expect(browser.activeTab?.internalPage != .whatsNew)
    }

    @Test func comparesVersionsNumerically() throws {
        let browser = browser(lastSeenVersion: "0.9.0")
        browser.announceUpdate(to: "0.10.0", releases: [try release("0.10.0")])
        #expect(browser.activeTab?.internalPage == .whatsNew)
    }

    @Test func freshInstallOnlyRecordsVersion() throws {
        let browser = browser(lastSeenVersion: nil, hasCompletedOnboarding: false)
        browser.announceUpdate(to: "0.3.0", releases: [try release("0.3.0")])
        #expect(browser.activeTab == nil)
        #expect(browser.preferences.lastSeenVersion == "0.3.0")
    }

    @Test func updatingFromBeforeWhatsNewExistedAnnounces() throws {
        let browser = browser(lastSeenVersion: nil)
        browser.announceUpdate(to: "0.3.0", releases: [try release("0.3.0")])
        #expect(browser.activeTab?.internalPage == .whatsNew)
    }

    @Test func releasesWithoutHighlightsStayQuiet() throws {
        let browser = browser(lastSeenVersion: "0.3.0")
        browser.announceUpdate(to: "0.3.1", releases: [try release("0.3.1", highlights: false)])
        #expect(browser.activeTab == nil)
    }

    @Test func downgradeStaysQuiet() throws {
        let browser = browser(lastSeenVersion: "0.4.0")
        browser.announceUpdate(to: "0.3.0", releases: [try release("0.3.0")])
        #expect(browser.activeTab == nil)
    }
}
