import Foundation
import Observation

enum SpaceTheme: String, CaseIterable {
    case purple, blue, green, orange, pink, graphite

    var displayName: String { rawValue.capitalized }
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

    init(
        id: UUID = UUID(),
        name: String,
        theme: SpaceTheme,
        icon: String? = nil,
        pinnedTabs: [Tab] = [],
        todayTabs: [Tab] = [],
        activeTabID: Tab.ID? = nil
    ) {
        self.id = id
        self.name = name
        self.theme = theme
        self.icon = icon
        self.pinnedTabs = pinnedTabs
        self.todayTabs = todayTabs
        self.activeTabID = activeTabID
    }

    var tabs: [Tab] { pinnedTabs + todayTabs }

    func contains(_ tab: Tab) -> Bool {
        tabs.contains { $0.id == tab.id }
    }
}
