import SwiftUI

/// The collapsed sidebar: a rail of favicons, like Chrome's collapsed vertical tabs,
/// so tabs stay one click away without giving up the page's width.
struct CollapsedSidebar: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        let space = browser.activeSpace
        VStack(spacing: 8) {
            Button(action: browser.toggleSidebar) {
                Image(systemName: "sidebar.left")
            }
            .accessibilityLabel("Expand Sidebar")
            .help("Expand Sidebar (⌘S)")
            Button { browser.showCommandBar(.editActiveTab) } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Open Location")
            .help("Open Location (⌘L)")

            ScrollView {
                VStack(spacing: 6) {
                    if !browser.favorites.isEmpty {
                        divider
                        ForEach(browser.favorites) { tab in
                            RailTab(tab: tab, isActive: tab.id == browser.activeTabID, isFavorite: true)
                        }
                    }
                    divider
                    ForEach(space.tabs) { tab in
                        RailTab(tab: tab, isActive: tab.id == space.activeTabID, isFavorite: false)
                    }
                    Button { browser.showCommandBar(.newTab) } label: {
                        Image(systemName: "plus")
                            .frame(width: Self.tileSize, height: Self.tileSize)
                    }
                    .accessibilityLabel("New Tab")
                    .help("New Tab (⌘T)")
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)

            VStack(spacing: 0) {
                ForEach(Array(browser.spaces.enumerated()), id: \.element.id) { index, space in
                    SpaceDot(space: space, isActive: space.id == browser.activeSpaceID)
                        .help(index < 9 ? "\(space.name) (⌃\(index + 1))" : space.name)
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .buttonStyle(SidebarIconButtonStyle())
        .foregroundStyle(Theme.sidebarText)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(width: Theme.collapsedSidebarWidth)
        .animation(.snappy(duration: 0.2), value: space.activeTabID)
        .animation(.snappy(duration: 0.22), value: space.tabs.map(\.id))
        .animation(.snappy(duration: 0.2), value: browser.activeSpaceID)
    }

    static let tileSize: CGFloat = 34

    private var divider: some View {
        Rectangle()
            .fill(Theme.sidebarText.opacity(0.12))
            .frame(width: 24, height: 1)
            .padding(.vertical, 2)
    }
}

/// A tab in the rail; favorites keep the tile outline they have in the expanded sidebar.
private struct RailTab: View {
    @Environment(Browser.self) private var browser
    let tab: Tab
    let isActive: Bool
    let isFavorite: Bool
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
        FaviconView(tab: tab, size: 16)
            .frame(width: CollapsedSidebar.tileSize, height: CollapsedSidebar.tileSize)
            .overlay(alignment: .topTrailing) {
                MediaCaptureIndicator(tab: tab)
                    .font(.system(size: 7, weight: .semibold))
                    .padding(2)
            }
            .background(shape.fill(isActive ? Theme.activeTabFill : isHovered ? Theme.hoverFill : .clear))
            .overlay(shape.strokeBorder(Theme.sidebarText.opacity(isFavorite ? 0.18 : 0)))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture { browser.select(tab) }
            .help(tab.displayTitle)
            .contextMenu { TabContextMenu(tab: tab) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tab.displayTitle)
            .accessibilityValue(tab.mediaCaptureDescription ?? "")
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { browser.select(tab) }
            .accessibilityAction(named: tab.isPinned ? "Reset Pinned Tab" : "Close Tab") { browser.close(tab) }
    }
}
