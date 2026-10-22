import SwiftUI

@main
struct PulseApp: App {
    @State private var browser = Browser(
        sessionStore: .standard,
        history: .standard(),
        sitePermissions: SitePermissionStore(defaults: .standard)
    )

    var body: some Scene {
        Window("Pulse", id: "browser") {
            BrowserWindow()
                .environment(browser)
                .onOpenURL(perform: browser.openExternalURL)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands { BrowserCommands(browser: browser) }
    }
}
