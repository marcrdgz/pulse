import Foundation
import Testing
import WebKit
@testable import Pulse

/// The store's own button talks to Pulse through the APIs Chrome gives it; these run them on a
/// stand-in page served from the store's origin, so nothing is downloaded.
struct ChromeWebStorePageTests {
    private let id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"
    private let store = URL(string: "https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh")!

    @Test func reportsAndRemovesInstalledExtensionsLikeChrome() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let extensions = WebExtensions(
            directory: directory,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString)),
            configuration: .nonPersistent()
        )
        let browser = Browser(extensions: extensions)
        try await extensions.install(from: try makeExtension(), identifier: id) { _ in true }
        var askedToRemove: String?
        extensions.confirmRemoval = { context in
            askedToRemove = context.webExtension.displayName
            return true
        }
        let tab = try await openStorePage(in: browser, html: "<button>Add to Chrome</button>")

        #expect(try await run("navigator.userAgent", in: tab) as? String == ChromeWebStorePage.userAgent(forPageAt: store))
        #expect(try await run("chrome.webstorePrivate.getExtensionStatus(id, '{}')", in: tab) as? String == "enabled")
        #expect(try await run("(await chrome.management.getAll()).map((e) => e.id)", in: tab) as? [String] == [id])

        let removed = try await run("""
            const removed = new Promise((resolve) => chrome.management.onUninstalled.addListener(resolve));
            await chrome.management.uninstall(id, { showConfirmDialog: true });
            return await removed;
            """, in: tab)
        #expect(removed as? String == id)
        #expect(askedToRemove == "Marker")
        #expect(extensions.contexts.isEmpty)
        #expect(try await run("chrome.webstorePrivate.getExtensionStatus(id, '{}')", in: tab) as? String == "installable")
    }

    @Test func callsTheButtonsPulseButLeavesOtherChromeProductsAlone() async throws {
        let browser = Browser(extensions: WebExtensions(
            directory: URL.temporaryDirectory.appending(path: UUID().uuidString),
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString)),
            configuration: .nonPersistent()
        ))
        let tab = try await openStorePage(in: browser, html: """
            <button><span>Añadir a Chrome</span></button><button>Try Chrome Enterprise Core</button><p>Add to Chrome</p>
            """)

        let labels = try await run("[...document.querySelectorAll('button, p')].map((e) => e.textContent)", in: tab)
        #expect(labels as? [String] == ["Añadir a Pulse", "Try Chrome Enterprise Core", "Add to Chrome"])
    }

    @Test func otherSitesGetNeitherTheAPIsNorChromesUserAgent() async throws {
        let browser = Browser(extensions: WebExtensions(
            directory: URL.temporaryDirectory.appending(path: UUID().uuidString),
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString)),
            configuration: .nonPersistent()
        ))
        let tab = browser.openTab(url: URL(string: "about:blank")!)
        tab.webView.loadHTMLString("<p>Page</p>", baseURL: URL(string: "https://example.com/detail/x/\(id)")!)
        try await waitUntilLoaded(tab)

        #expect(try await run("typeof window.chrome?.webstorePrivate", in: tab) as? String == "undefined")
        #expect(try await run("navigator.userAgent.includes('Chrome/')", in: tab) as? Bool == false)
        // Claims the installed Safari, so the app must be able to read its version.
        let safari = try #require(Bundle(url: URL(filePath: "/Applications/Safari.app")))
        let version = try #require(safari.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        #expect((try await run("navigator.userAgent", in: tab) as? String)?.hasSuffix("Version/\(version) Safari/605.1.15") == true)
        #expect(ChromeWebStorePage.userAgent(forPageAt: URL(string: "https://example.com")!) == nil)
    }

    @Test func acceptsOnlyWellFormedRequests() {
        func request(_ body: Any) -> String? { ChromeWebStorePage.Request(body).map { "\($0)" } }
        #expect(request(["install", ["id": id, "manifest": "{}"]]) == "install(id: \"\(id)\")")
        #expect(request(["status", id]) == "status(id: \"\(id)\")")
        #expect(request(["installed", NSNull()]) == "installed")
        #expect(request(["install", ["id": "../../etc"]]) == nil)
        #expect(request(["delete", id]) == nil)
        #expect(request("install") == nil)
    }

    // MARK: Helpers

    private func openStorePage(in browser: Browser, html: String) async throws -> Tab {
        let tab = browser.openTab(url: URL(string: "about:blank")!)
        tab.webView.loadHTMLString(html, baseURL: store)
        try await waitUntilLoaded(tab)
        return tab
    }

    private func waitUntilLoaded(_ tab: Tab) async throws {
        for _ in 0..<100 where try await run("document.readyState", in: tab) as? String != "complete" {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Runs `script` as the page's own code would, with `id` in scope; a single expression is returned.
    private func run(_ script: String, in tab: Tab) async throws -> Any? {
        let body = script.contains("return ") ? script : "return await (\(script));"
        return try await tab.webView.callAsyncJavaScript(body, arguments: ["id": id], contentWorld: .page)
    }

    private func makeExtension() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Marker", "version": "1.0"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: "manifest.json"))
        return folder
    }
}
