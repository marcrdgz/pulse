import Foundation
import Observation

enum SpaceTheme: String, CaseIterable {
    case purple, blue, green, orange, pink, graphite

    var displayName: String { rawValue.capitalized }
}

/// Two tabs of a space shown side by side, listed as one sidebar row in the leading tab's place.
struct TabSplit: Codable, Equatable {
    var leading: Tab.ID
    var trailing: Tab.ID
    /// The leading pane's share of the width.
    var ratio = 0.5

    static let ratioRange = 0.2...0.8

    func contains(_ id: Tab.ID?) -> Bool {
        id == leading || id == trailing
    }

    func partner(of id: Tab.ID) -> Tab.ID? {
        id == leading ? trailing : id == trailing ? leading : nil
    }
}

/// A sidebar of its own: pinned and today tabs plus the tab last shown in it.
/// Favorites are shared by every space and live in `Browser`.
@Observable
final class Space: Identifiable {
    let id: UUID
    var name: String
    var theme: SpaceTheme
    /// An emoji shown instead of the color dot.
    var icon: String?
    var pinnedTabs: [Tab]
    /// Newest first, like Arc's "Today" section.
    var todayTabs: [Tab]
    /// May point at a favorite: each space remembers what it was showing.
    var activeTabID: Tab.ID?
    /// A tab is in at most one split.
    var splits: [TabSplit]

    init(
        id: UUID = UUID(),
        name: String,
        theme: SpaceTheme,
        icon: String? = nil,
        pinnedTabs: [Tab] = [],
        todayTabs: [Tab] = [],
        activeTabID: Tab.ID? = nil,
        splits: [TabSplit] = []
    ) {
        self.id = id
        self.name = name
        self.theme = theme
        self.icon = icon
        self.pinnedTabs = pinnedTabs
        self.todayTabs = todayTabs
        self.activeTabID = activeTabID
        self.splits = splits
        removeStaleSplits()
    }

    var tabs: [Tab] { pinnedTabs + todayTabs }

    func contains(_ tab: Tab) -> Bool {
        tabs.contains { $0.id == tab.id }
    }

    func split(containing id: Tab.ID?) -> TabSplit? {
        splits.first { $0.contains(id) }
    }

    func tab(withID id: Tab.ID) -> Tab? {
        tabs.first { $0.id == id }
    }

    /// Drops splits whose tabs left the space, or that reuse a tab already in another split.
    func removeStaleSplits() {
        var seen: Set<Tab.ID> = []
        splits = splits.filter { split in
            split.leading != split.trailing && tab(withID: split.leading) != nil && tab(withID: split.trailing) != nil
                && seen.insert(split.leading).inserted && seen.insert(split.trailing).inserted
        }
    }
}
