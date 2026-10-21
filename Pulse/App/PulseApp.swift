import SwiftUI

@main
struct PulseApp: App {
    @State private var browser = Browser(sessionStore: .standard)

    var body: some Scene {
        Window("Pulse", id: "browser") {
            BrowserWindow()
                .environment(browser)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands { BrowserCommands(browser: browser) }
    }
}
