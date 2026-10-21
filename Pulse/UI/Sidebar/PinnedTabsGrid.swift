import SwiftUI

/// Pinned tabs as a grid of favicon tiles at the top of the sidebar.
struct PinnedTabsGrid: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
            ForEach(browser.pinnedTabs) { tab in
                PinnedTabTile(tab: tab, isActive: tab.id == browser.activeTabID)
                    .onTapGesture { browser.select(tab) }
                    .contextMenu { TabContextMenu(tab: tab) }
            }
        }
    }
}

private struct PinnedTabTile: View {
    let tab: Tab
    let isActive: Bool
    @State private var isHovered = false

    var body: some View {
        FaviconView(tab: tab, size: 18)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive || isHovered ? Theme.activeTabFill : Theme.pillFill)
                    .shadow(color: .black.opacity(isActive ? 0.08 : 0), radius: 1, y: 1)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .help(tab.displayTitle)
    }
}
