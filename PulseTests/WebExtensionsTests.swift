import Foundation
import Testing
import WebKit
@testable import Pulse

struct WebExtensionsTests {
    private let site = URL(string: "https://example.com/")!

    @Test func runsContentScriptsOfAnInstalledExtensionAcrossLaunches() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let source = try makeExtension(matching: "https://example.com/*")

        let extensions = makeExtensions(in: directory, defaults: defaults)
        let browser = Browser(extensions: extensions)
        var asked: String?
        let context = try await extensions.install(from: source) { candidate in
            asked = candidate.displayName
            return true
        }
        #expect(asked == "Marker")
        #expect(context?.isLoaded == true)
        #expect(extensions.contexts.count == 1)
        try await expectMarker(in: browser.openTab(url: URL(string: "about:blank")!))

        // A later launch loads it from disk with the permissions granted at install.
        let relaunched = makeExtensions(in: directory, defaults: defaults)
        let relaunchedBrowser = Browser(extensions: relaunched)
        await relaunched.loadInstalled()
        #expect(relaunched.contexts.map(\.uniqueIdentifier) == [context?.uniqueIdentifier])
        try await expectMarker(in: relaunchedBrowser.openTab(url: URL(string: "about:blank")!))
    }

    @Test func installsNothingWhenNotConfirmed() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let extensions = makeExtensions(in: directory, defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))

        let context = try await extensions.install(from: try makeExtension(matching: "https://example.com/*")) { _ in false }

        #expect(context == nil)
        #expect(extensions.contexts.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path()))
    }

    @Test func reinstallingReplacesAndUninstallingRemovesTheFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let extensions = makeExtensions(in: directory, defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let id = String(repeating: "a", count: 32)

        try await extensions.install(from: try makeExtension(matching: "https://example.com/*"), identifier: id) { _ in true }
        let update = try #require(try await extensions.install(
            from: try makeExtension(matching: "https://example.com/*", version: "2.0"),
            identifier: id
        ) { _ in true })
        #expect(extensions.contexts.map(\.webExtension.version) == ["2.0"])

        await extensions.uninstall(update)
        #expect(extensions.contexts.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path()).isEmpty)
    }

    @Test func rejectsAnInvalidExtensionWithoutAsking() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let extensions = makeExtensions(in: directory, defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let source = temporaryDirectory()
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: source.appending(path: "manifest.json"))

        await #expect(throws: (any Error).self) {
            try await extensions.install(from: source) { _ in
                Issue.record("Asked to install an invalid extension")
                return true
            }
        }
        #expect(extensions.contexts.isEmpty)
    }

    @Test func describesPermissionsLikeChrome() throws {
        let some = try Set(["https://*.github.com/*", "https://example.com/*", "https://news.ycombinator.com/*"]
            .map { try WKWebExtension.MatchPattern(string: $0) })
        #expect(WebExtensions.permissionDescriptions(for: [.tabs, .storage], matchPatterns: some) == [
            "Read and change your data on example.com, github.com and 1 other sites",
            "Read your browsing history",
        ])
        #expect(WebExtensions.permissionDescriptions(for: [.storage], matchPatterns: [.allURLs()]) == [
            "Read and change all your data on all websites",
        ])
        #expect(WebExtensions.permissionDescriptions(for: [.storage, .alarms], matchPatterns: []).isEmpty)
    }

    // MARK: Chrome Web Store

    @Test func findsTheExtensionOnAStorePage() {
        let id = "nngceckbapebfimnlniiiahkandclblb"
        let pages = [
            "https://chromewebstore.google.com/detail/bitwarden-password-manager/\(id)",
            "https://chromewebstore.google.com/detail/\(id)?hl=en",
            "https://chrome.google.com/webstore/detail/bitwarden/\(id)",
        ]
        for page in pages {
            #expect(ChromeWebStore.extensionID(fromStorePage: URL(string: page)!) == id)
        }
        #expect(ChromeWebStore.extensionID(fromStorePage: URL(string: "https://chromewebstore.google.com/category/extensions")!) == nil)
        #expect(ChromeWebStore.extensionID(fromStorePage: URL(string: "https://example.com/detail/\(id)")!) == nil)
    }

    @Test func unwrapsTheZIPArchiveOfCRXPackages() throws {
        let zip = Data("PK\u{3}\u{4}archive".utf8)
        let crx3 = Data("Cr24".utf8) + littleEndian(3) + littleEndian(5) + Data(repeating: 0, count: 5) + zip
        let crx2 = Data("Cr24".utf8) + littleEndian(2) + littleEndian(3) + littleEndian(2) + Data(repeating: 0, count: 5) + zip

        #expect(try ChromeWebStore.zipArchive(fromPackage: crx3) == zip)
        #expect(try ChromeWebStore.zipArchive(fromPackage: crx2) == zip)
        #expect(throws: ChromeWebStore.PackageError.self) { try ChromeWebStore.zipArchive(fromPackage: zip) }
        #expect(throws: ChromeWebStore.PackageError.self) { try ChromeWebStore.zipArchive(fromPackage: crx3.prefix(14)) }
    }

    // MARK: Helpers

    private func makeExtensions(in directory: URL, defaults: UserDefaults) -> WebExtensions {
        WebExtensions(directory: directory, defaults: defaults, configuration: .nonPersistent())
    }

    /// A content script that marks the pages it runs on.
    private func makeExtension(matching pattern: String, version: String = "1.0") throws -> URL {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Marker",
            "version": version,
            "content_scripts": [["matches": [pattern], "js": ["marker.js"], "run_at": "document_end"]],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: "manifest.json"))
        try Data("document.documentElement.dataset.marker = 'on'".utf8).write(to: folder.appending(path: "marker.js"))
        return folder
    }

    private func expectMarker(in tab: Tab) async throws {
        tab.webView.loadHTMLString("<p>Page</p>", baseURL: site)
        for _ in 0..<100 where await marker(in: tab) != "on" {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(await marker(in: tab) == "on")
    }

    private func marker(in tab: Tab) async -> String? {
        try? await tab.webView.evaluateJavaScript("document.documentElement.dataset.marker ?? null") as? String
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
