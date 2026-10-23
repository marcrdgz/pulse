import SwiftUI

/// Drag-to-reorder for sidebar tabs, in window (`.global`) coordinates.
///
/// Within a section the model is reordered live, so neighbours slide out of the way like in Arc.
/// Crossing sections (favorites, pinned, today) only happens on drop: they are different
/// containers, and moving the model mid-drag would tear down the view owning the gesture.
@Observable
final class SidebarDragController {
    private(set) var draggedTabID: Tab.ID?
    /// The section the tab will move to on drop when it differs from its own.
    private(set) var pendingSection: TabSection?
    private(set) var location: CGPoint = .zero
    private(set) var grabOffset: CGSize = .zero
    /// Whether empty sections show their drop zones. They open only once the pointer leaves the
    /// dragged tab's section upwards, where they live: opening them on pickup would push the rows
    /// under the pointer down and turn a quick reorder into a move to the wrong slot.
    private(set) var showsDropZones = false
    /// The space whose dot is under the pointer; its name shows above it, since dots only differ by color.
    private(set) var hoveredSpaceID: Space.ID?
    /// Over the space switcher a drop moves the tab to the hovered space instead of a section.
    @ObservationIgnored private var isOverSpaceSwitcher = false

    // Layout reports; not observed so frame updates don't re-render the sidebar.
    @ObservationIgnored var tabFrames: [Tab.ID: CGRect] = [:]
    @ObservationIgnored var favoritesAreaFrame: CGRect?
    @ObservationIgnored var pinnedAreaFrame: CGRect?
    @ObservationIgnored var todayAreaFrame: CGRect?
    /// The visible part of the active space's scrolling list; rows scrolled out of it can't be hit.
    @ObservationIgnored var scrollViewportFrame: CGRect?
    @ObservationIgnored var spaceSwitcherFrame: CGRect?
    @ObservationIgnored var spaceDotFrames: [Space.ID: CGRect] = [:]

    var isDragging: Bool { draggedTabID != nil }

    func drag(_ tab: Tab, to location: CGPoint, in browser: Browser) {
        if draggedTabID != tab.id {
            let frame = tabFrames[tab.id] ?? CGRect(origin: location, size: .zero)
            grabOffset = CGSize(width: location.x - frame.midX, height: location.y - frame.midY)
            draggedTabID = tab.id
        }
        self.location = location

        guard let source = browser.position(of: tab) else {
            pendingSection = nil
            return
        }
        if updateSpaceHover(source: source, at: location, in: browser) {
            pendingSection = nil
            return
        }
        if !showsDropZones, hasLeftUpwards(source.section, at: location) {
            withAnimation(.snappy(duration: 0.22)) { showsDropZones = true }
        }
        guard let destination = destination(for: tab, at: location, in: browser) else {
            pendingSection = nil
            return
        }
        if destination.section == source.section {
            pendingSection = nil
            if destination != source {
                withAnimation(.snappy(duration: 0.2)) { browser.moveTab(tab, to: destination) }
            }
        } else {
            pendingSection = destination.section
        }
    }

    func drop(_ tab: Tab, at location: CGPoint, in browser: Browser) {
        let isOverSpaceSwitcher = isOverSpaceSwitcher
        let targetSpace = browser.spaces.first { $0.id == hoveredSpaceID && $0.id != browser.activeSpaceID }
        let source = browser.position(of: tab)
        let destination = destination(for: tab, at: location, in: browser)
        // End first: a view inserted while it is still dimmed as the drag placeholder
        // can keep that opacity once the insertion animation runs.
        endDrag()
        if isOverSpaceSwitcher {
            if let targetSpace {
                withAnimation(.snappy(duration: 0.25)) { browser.moveTab(tab, to: targetSpace) }
            }
        } else if let source, let destination, destination.section != source.section {
            withAnimation(.snappy(duration: 0.25)) { browser.moveTab(tab, to: destination) }
        }
    }

    /// Also called when the gesture is cancelled, so it must be idempotent.
    func endDrag() {
        guard isDragging else { return }
        withAnimation(.snappy(duration: 0.2)) {
            draggedTabID = nil
            pendingSection = nil
            showsDropZones = false
            hoveredSpaceID = nil
        }
        isOverSpaceSwitcher = false
    }

    /// Returns whether the pointer is over the space switcher, which takes over from the sections.
    private func updateSpaceHover(source: TabPosition, at location: CGPoint, in browser: Browser) -> Bool {
        // Favorites belong to no space, as in "Move to Space".
        guard source.section != .favorites, browser.spaces.count > 1,
              spaceSwitcherFrame?.insetBy(dx: 0, dy: -6).contains(location) ?? false
        else {
            isOverSpaceSwitcher = false
            hoveredSpaceID = nil
            return false
        }
        isOverSpaceSwitcher = true
        hoveredSpaceID = browser.spaces.first { spaceDotFrames[$0.id]?.contains(location) ?? false }?.id
        return true
    }

    /// Favorites sit above everything, so zones opening below them never move their tiles.
    private func hasLeftUpwards(_ section: TabSection, at location: CGPoint) -> Bool {
        let sectionTop: CGFloat? = switch section {
        case .favorites: .infinity
        case .pinned: pinnedAreaFrame?.minY
        case .today: todayAreaFrame?.minY
        }
        guard let sectionTop else { return false }
        return location.y < sectionTop - 6
    }

    func tab(at location: CGPoint, in browser: Browser) -> Tab? {
        let isInViewport = scrollViewportFrame?.contains(location) ?? false
        let candidates = browser.favorites + (isInViewport ? browser.activeSpace.tabs : [])
        return candidates.first { tabFrames[$0.id]?.contains(location) ?? false }
    }

    private func destination(for tab: Tab, at location: CGPoint, in browser: Browser) -> TabPosition? {
        if let favoritesAreaFrame, favoritesAreaFrame.insetBy(dx: 0, dy: -6).contains(location) {
            // Grid insertion point in reading order: before the first tile the pointer is above or left of.
            let others = browser.favorites.filter { $0.id != tab.id }
            let index = others.firstIndex { other in
                guard let frame = tabFrames[other.id] else { return false }
                return location.y < frame.minY || (location.y < frame.maxY && location.x < frame.midX)
            } ?? others.count
            return TabPosition(section: .favorites, index: index)
        }
        if let pinnedAreaFrame, pinnedAreaFrame.insetBy(dx: 0, dy: -6).contains(location) {
            return TabPosition(section: .pinned, index: listIndex(at: location, in: browser.pinnedTabs, excluding: tab))
        }
        if let todayAreaFrame, location.y >= todayAreaFrame.minY - 6 {
            return TabPosition(section: .today, index: listIndex(at: location, in: browser.todayTabs, excluding: tab))
        }
        return nil
    }

    private func listIndex(at location: CGPoint, in tabs: [Tab], excluding tab: Tab) -> Int {
        tabs.filter { $0.id != tab.id && (tabFrames[$0.id]?.midY ?? .infinity) < location.y }.count
    }
}

private struct DraggableSidebarTab: ViewModifier {
    @Environment(Browser.self) private var browser
    @Environment(SidebarDragController.self) private var dragController
    @GestureState private var isGestureActive = false
    let tab: Tab

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                dragController.tabFrames[tab.id] = frame
            }
            // The ghost follows the pointer; the original stays as a placeholder in its slot.
            .opacity(dragController.draggedTabID == tab.id ? 0.35 : 1)
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .updating($isGestureActive) { _, isActive, _ in isActive = true }
                    .onChanged { dragController.drag(tab, to: $0.location, in: browser) }
                    .onEnded { dragController.drop(tab, at: $0.location, in: browser) }
            )
            .onChange(of: isGestureActive) {
                if !isGestureActive { dragController.endDrag() }
            }
    }
}

extension View {
    func sidebarDraggable(_ tab: Tab) -> some View {
        modifier(DraggableSidebarTab(tab: tab))
    }
}

/// A dashed slot shown in an empty section while a tab is dragged, so it can be dropped there.
struct SidebarDropZone: View {
    let title: String
    let isTargeted: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12))
            .opacity(0.6)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                    .fill(isTargeted ? Theme.hoverFill : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .opacity(0.45)
            )
    }
}

/// The floating copy of the dragged tab.
struct SidebarDragGhost: View {
    let tab: Tab
    let isTile: Bool
    let size: CGSize

    var body: some View {
        Group {
            if isTile {
                FaviconView(tab: tab, size: 18)
            } else {
                HStack(spacing: 8) {
                    FaviconView(tab: tab, size: 16)
                    Text(tab.displayTitle)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(Theme.activeTabFill)
                .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        )
        .scaleEffect(1.04)
        .allowsHitTesting(false)
    }
}
