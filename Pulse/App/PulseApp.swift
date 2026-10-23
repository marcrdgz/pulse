import SwiftUI

@main
struct PulseApp: App {
    @State private var browser: Browser = {
        let preferences = Preferences(defaults: .standard)
        let supportDirectory = URL.applicationSupportDirectory.appending(path: "Pulse", directoryHint: .isDirectory)
        let browser = Browser(
            sessionStore: .standard,
            history: .standard(),
            sitePermissions: SitePermissionStore(defaults: .standard),
            downloads: DownloadManager(recordsURL: supportDirectory.appending(path: "Downloads.json"), preferences: preferences),
            contentBlocker: ContentBlocker(store: .default(), defaults: .standard, preferences: preferences),
            preferences: preferences
        )
        browser.startHibernatingInactiveTabs()
        return browser
    }()

    var body: some Scene {
        Window("Pulse", id: "browser") {
            BrowserWindow()
                .environment(browser)
                .onOpenURL(perform: browser.openExternalURL)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands { BrowserCommands(browser: browser) }

        Settings {
            SettingsView()
                .environment(browser)
        }
    }
}
