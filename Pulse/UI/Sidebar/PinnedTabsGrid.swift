import SwiftUI

/// Pinned tabs as a grid of favicon tiles at the top of the sidebar.
/// While a today tab is dragged it doubles as the drop zone for pinning.
struct PinnedTabsGrid: View {
    @Environment(Browser.self) private var browser
    @Environment(SidebarDragController.self) private var dragController

    private var isDropTarget: Bool { dragController.pendingSection == .pinned }

    var body: some View {
        Group {
            if browser.pinnedTabs.isEmpty {
                Text("Drop here to pin")
                    .font(.system(size: 12))
                    .opacity(0.6)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
                    ForEach(browser.pinnedTabs) { tab in
                        PinnedTabTile(tab: tab, isActive: tab.id == browser.activeTabID)
                            .onTapGesture { browser.select(tab) }
                            .contextMenu { TabContextMenu(tab: tab) }
                            .sidebarDraggable(tab)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDropTarget ? Theme.hoverFill : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .opacity(isDropTarget || browser.pinnedTabs.isEmpty ? 0.45 : 0)
        )
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            dragController.pinnedAreaFrame = frame
        }
        .onDisappear { dragController.pinnedAreaFrame = nil }
        .animation(.snappy(duration: 0.22), value: browser.pinnedTabs.map(\.id))
        .animation(.snappy(duration: 0.15), value: isDropTarget)
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

