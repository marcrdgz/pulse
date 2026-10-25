import SwiftUI

/// Favorites, shared by every space, as a grid of favicon tiles at the top of the sidebar.
/// While a tab is dragged it doubles as the drop zone for adding favorites.
struct FavoritesGrid: View {
    @Environment(Browser.self) private var browser
    @Environment(SidebarDragController.self) private var dragController

    private var isDropTarget: Bool { dragController.pendingSection == .favorites }

    var body: some View {
        Group {
            if browser.favorites.isEmpty {
                SidebarDropZone(title: "Drop here to add to Favorites", isTargeted: isDropTarget)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
                    ForEach(dragController.items(browser.favorites, in: .favorites)) { item in
                        switch item {
                        case .tab(let tab): tile(for: tab)
                        case .slot: SidebarDropSlot(isTile: true)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.tileCornerRadius, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .opacity(isDropTarget ? 0.45 : 0)
                )
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            dragController.favoritesAreaFrame = frame
        }
        .onDisappear { dragController.favoritesAreaFrame = nil }
        .animation(.snappy(duration: 0.22), value: browser.favorites.map(\.id))
        .animation(.snappy(duration: 0.15), value: isDropTarget)
    }

    private func tile(for tab: Tab) -> some View {
        FavoriteTile(tab: tab, isActive: tab.id == browser.activeTabID)
            .onTapGesture { browser.select(tab) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tab.displayTitle)
            .accessibilityValue(tab.mediaDescription ?? "")
            .accessibilityAddTraits(tab.id == browser.activeTabID ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { browser.select(tab) }
            .contextMenu { TabContextMenu(tab: tab) }
            .sidebarDraggable(tab)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

private struct FavoriteTile: View {
    let tab: Tab
    let isActive: Bool
    @State private var isHovered = false

    var body: some View {
        FaviconView(tab: tab, size: 18)
            .frame(maxWidth: .infinity, minHeight: Theme.tileHeight)
            .overlay(alignment: .topTrailing) {
                MediaCaptureIndicator(tab: tab)
                    .font(.system(size: 8, weight: .semibold))
                    .padding(5)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.tileCornerRadius, style: .continuous)
                    .fill(isActive || isHovered ? Theme.activeTabFill : Theme.pillFill)
                    .shadow(color: .black.opacity(isActive ? 0.08 : 0), radius: 1, y: 1)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .help(tab.displayTitle)
    }
}
