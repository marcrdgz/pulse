import Foundation

/// Something the command bar does besides opening pages, like Arc's command bar actions.
struct CommandBarAction: Identifiable {
    enum Kind: Hashable {
        case copyURL
        case togglePin
        case toggleFavorite
        case duplicateTab
        case closeTab
        case closeOtherTabs
        case reload
        case findOnPage
        case toggleContentBlocking
        case moveTab(to: Space.ID)
        case switchToSpace(Space.ID)
        case newSpace
        case toggleSidebar
        case reopenClosedTab
        case showHistory
        case showDownloads
        case clearBrowsingData
        case openSettings
        case showWebInspector
    }

    let kind: Kind
    let title: String
    /// An SF Symbol.
    let symbol: String
    /// Other words people search for it by.
    var keywords: [String] = []
    /// The menu shortcut, shown as a reminder.
    var shortcut: String?

    var id: Kind { kind }

    /// Every word typed must start a word of the title or the keywords: "cl ot" finds "Close Other Tabs".
    func matches(_ query: String) -> Bool {
        let words = (title.lowercased().split(separator: " ") + keywords.map { Substring($0) })
        let typed = query.lowercased().split(separator: " ")
        return !typed.isEmpty && typed.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
    }
}

extension Browser {
    /// The actions that make sense right now, most specific to the current tab first.
    var commandBarActions: [CommandBarAction] {
        typealias Action = CommandBarAction
        let otherSpaces = spaces.filter { $0.id != activeSpaceID }
        var actions: [Action] = []
        if let tab = activeTab {
            let section = position(of: tab)?.section
            actions += [
                Action(kind: .copyURL, title: "Copy URL", symbol: "link", keywords: ["link", "address"], shortcut: "⇧⌘C"),
                Action(kind: .togglePin, title: section == .pinned ? "Unpin Tab" : "Pin Tab", symbol: "pin", shortcut: "⌘D"),
                Action(
                    kind: .toggleFavorite,
                    title: section == .favorites ? "Remove from Favorites" : "Add to Favorites",
                    symbol: "star"
                ),
                Action(kind: .duplicateTab, title: "Duplicate Tab", symbol: "plus.square.on.square", keywords: ["copy"]),
                Action(kind: .closeTab, title: tab.isPinned ? "Reset Pinned Tab" : "Close Tab", symbol: "xmark", shortcut: "⌘W"),
                Action(kind: .closeOtherTabs, title: "Close Other Tabs", symbol: "xmark.square"),
                Action(kind: .reload, title: "Reload Page", symbol: "arrow.clockwise", keywords: ["refresh"], shortcut: "⌘R"),
                Action(kind: .findOnPage, title: "Find on Page", symbol: "text.magnifyingglass", keywords: ["text"], shortcut: "⌘F"),
            ]
            if contentBlocker.isEnabled, tab.url.isWebPage, let site = tab.url.displayHost {
                let isBlocking = contentBlocker.isBlocking(on: tab.url)
                actions.append(Action(
                    kind: .toggleContentBlocking,
                    title: isBlocking ? "Allow Ads on \(site)" : "Block Ads on \(site)",
                    symbol: isBlocking ? "shield.slash" : "shield",
                    keywords: ["adblock", "blocker", "trackers"]
                ))
            }
            actions += otherSpaces.map { space in
                Action(
                    kind: .moveTab(to: space.id),
                    title: "Move Tab to \(space.name)",
                    symbol: "arrow.right.square",
                    keywords: ["space"]
                )
            }
        }
        actions += otherSpaces.map { space in
            Action(
                kind: .switchToSpace(space.id),
                title: "Switch to \(space.name)",
                symbol: "square.stack",
                keywords: ["space", "go"]
            )
        }
        actions += [
            Action(kind: .newSpace, title: "New Space", symbol: "plus.rectangle.on.rectangle", keywords: ["create"]),
            Action(
                kind: .toggleSidebar,
                title: isSidebarExpanded ? "Hide Sidebar" : "Show Sidebar",
                symbol: "sidebar.left",
                keywords: ["toggle", "collapse"],
                shortcut: "⌘S"
            ),
        ]
        if canReopenClosedTab {
            actions.append(Action(
                kind: .reopenClosedTab,
                title: "Reopen Closed Tab",
                symbol: "arrow.uturn.backward",
                keywords: ["undo", "restore"],
                shortcut: "⇧⌘T"
            ))
        }
        actions += [
            Action(kind: .showHistory, title: "Show History", symbol: "clock", shortcut: "⌘Y"),
            Action(kind: .showDownloads, title: "Show Downloads", symbol: "arrow.down.circle", shortcut: "⇧⌘J"),
            Action(
                kind: .clearBrowsingData,
                title: "Clear Browsing Data",
                symbol: "trash",
                keywords: ["cookies", "cache", "delete"],
                shortcut: "⇧⌘⌫"
            ),
            Action(
                kind: .openSettings,
                title: "Open Settings",
                symbol: "gearshape",
                keywords: ["preferences", "options"],
                shortcut: "⌘,"
            ),
        ]
        if activeTab != nil {
            actions.append(Action(
                kind: .showWebInspector,
                title: "Show Web Inspector",
                symbol: "hammer",
                keywords: ["devtools", "developer", "inspect"],
                shortcut: "⌥⌘I"
            ))
        }
        return actions
    }

    /// Runs an action on the active tab; `.openSettings` needs SwiftUI's `openSettings` and is the view's job.
    func perform(_ action: CommandBarAction.Kind) {
        dismissCommandBar()
        let tab = activeTab
        switch action {
        case .copyURL: if let tab { copyURL(of: tab) }
        case .togglePin: if let tab { togglePin(tab) }
        case .toggleFavorite: if let tab { toggleFavorite(tab) }
        case .duplicateTab: if let tab { duplicate(tab) }
        case .closeTab: closeActiveTab()
        case .closeOtherTabs: if let tab { closeOtherTabs(than: tab) }
        case .reload: tab?.reload()
        case .findOnPage: showFindBar()
        case .toggleContentBlocking: if let tab { toggleContentBlocking(on: tab) }
        case .moveTab(let spaceID):
            if let tab, let space = spaces.first(where: { $0.id == spaceID }) { moveTab(tab, to: space) }
        case .switchToSpace(let spaceID):
            if let space = spaces.first(where: { $0.id == spaceID }) { selectSpace(space) }
        case .newSpace: createSpace()
        case .toggleSidebar: toggleSidebar()
        case .reopenClosedTab: reopenClosedTab()
        case .showHistory: showHistory()
        case .showDownloads: showDownloads()
        case .clearBrowsingData: showClearBrowsingData()
        case .openSettings: break
        case .showWebInspector: tab?.showWebInspector()
        }
    }
}
