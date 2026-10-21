import SwiftUI

/// Every keyboard shortcut lives here, as a menu item, mirroring Arc's bindings.
struct BrowserCommands: Commands {
    let browser: Browser

    private var activeTab: Tab? { browser.activeTab }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { browser.showCommandBar(.newTab) }
                .keyboardShortcut("t")
            Button("Open Location…") { browser.showCommandBar(.editActiveTab) }
                .keyboardShortcut("l")
            Divider()
            Button(activeTab?.isPinned == true ? "Reset Pinned Tab" : "Close Tab", action: browser.closeActiveTab)
                .keyboardShortcut("w")
                .disabled(activeTab == nil)
            Button("Reopen Closed Tab", action: browser.reopenClosedTab)
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!browser.canReopenClosedTab)
        }

        // The system "Close" item also binds ⌘W and would win over "Close Tab", closing the only window.
        CommandGroup(replacing: .saveItem) {}

        CommandGroup(replacing: .sidebar) {
            Button(browser.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar", action: browser.toggleSidebar)
                .keyboardShortcut("s")
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Button("Reload Page") { activeTab?.reload() }
                .keyboardShortcut("r")
                .disabled(activeTab == nil)
            Button("Reload Page Ignoring Cache") { activeTab?.reload(ignoringCache: true) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(activeTab == nil)
            Divider()
            Button("Actual Size") { activeTab?.resetZoom() }
                .keyboardShortcut("0")
            Button("Zoom In") { activeTab?.zoomIn() }
                .keyboardShortcut("=")
            Button("Zoom Out") { activeTab?.zoomOut() }
                .keyboardShortcut("-")
        }

        CommandMenu("History") {
            Button("Back") { activeTab?.goBack() }
                .keyboardShortcut("[")
                .disabled(!(activeTab?.canGoBack ?? false))
            Button("Forward") { activeTab?.goForward() }
                .keyboardShortcut("]")
                .disabled(!(activeTab?.canGoForward ?? false))
        }

        CommandMenu("Tabs") {
            Button(activeTab?.isPinned == true ? "Unpin Tab" : "Pin Tab") {
                if let activeTab { browser.togglePin(activeTab) }
            }
            .keyboardShortcut("d")
            .disabled(activeTab == nil)
            Button("Copy URL") {
                if let activeTab { browser.copyURL(of: activeTab) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(activeTab == nil)

            Divider()
            Button("Next Tab") { browser.selectAdjacentTab(offset: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Previous Tab") { browser.selectAdjacentTab(offset: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Cycle to Next Tab") { browser.selectAdjacentTab(offset: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Cycle to Previous Tab") { browser.selectAdjacentTab(offset: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])

            Divider()
            ForEach(1..<10) { number in
                Button(number == 9 ? "Select Last Tab" : "Select Tab \(number)") {
                    browser.selectTab(number: number)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))))
            }
        }

        CommandMenu("Develop") {
            Button("Web Inspector") { activeTab?.showWebInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(activeTab == nil)
        }
    }
}
