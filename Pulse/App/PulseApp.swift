import SwiftUI

@main
struct PulseApp: App {
    @State private var browser: Browser = {
        SandboxContainerMigration.run(
            bundleID: Bundle.main.bundleIdentifier ?? "dev.doblefilo.pulse",
            home: .homeDirectory,
            defaults: .standard
        )
        let preferences = Preferences(defaults: .standard)
        let supportDirectory = URL.pulseSupportDirectory
        let extensions = WebExtensions(
            directory: supportDirectory.appending(path: "Extensions", directoryHint: .isDirectory),
            defaults: .standard
        )
        let browser = Browser(
            sessionStore: .standard,
            history: .standard(),
            sitePermissions: SitePermissionStore(defaults: .standard),
            downloads: DownloadManager(recordsURL: supportDirectory.appending(path: "Downloads.json"), preferences: preferences),
            contentBlocker: ContentBlocker(store: .default(), defaults: .standard, preferences: preferences),
            extensions: extensions,
            preferences: preferences
        )
        browser.startHibernatingInactiveTabs()
        Task { await extensions.loadInstalled() }
        Task { await browser.removeDeletedProfilesData() }
        return browser
    }()

    var body: some Scene {
        Window("Pulse", id: "browser") {
            BrowserWindow()
                .environment(browser)
                .focusedSceneValue(\.browser, browser)
                .onOpenURL(perform: browser.openExternalURL)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands { BrowserCommands(mainBrowser: browser) }

        WindowGroup("Private Window", id: PrivateBrowserWindow.id) {
            PrivateBrowserWindow(contentBlocker: browser.contentBlocker, preferences: browser.preferences)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        // Links from other apps belong in the main window, never in a new private one.
        .handlesExternalEvents(matching: [])

        Settings {
            SettingsView()
                .environment(browser)
        }
    }
}
