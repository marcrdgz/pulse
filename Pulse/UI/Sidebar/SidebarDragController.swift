import SwiftUI

/// Drag-to-reorder for sidebar tabs, in window (`.global`) coordinates.
///
/// Within a section the model is reordered live, so neighbours slide out of the way like in Arc.
/// Crossing sections (favorites, pinned, today) only happens on drop: they are different
/// containers, and moving the model mid-drag would tear down the view owning the gesture. Until
/// then the target section opens a slot where the tab will land, so it reads the same way.
@Observable
final class SidebarDragController {
    private(set) var draggedTabID: Tab.ID?
    /// Where the tab will move on drop when that's another section than its own.
    private(set) var pendingDestination: TabPosition?
    var pendingSection: TabSection? { pendingDestination?.section }
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
    /// How far each space's list is scrolled, and can be.
    @ObservationIgnored var listScrollRanges: [Space.ID: ListScrollRange] = [:]
    @ObservationIgnored var spaceSwitcherFrame: CGRect?
    @ObservationIgnored var spaceDotFrames: [Space.ID: CGRect] = [:]

    /// Over the page, the side the dragged tab would open on in a split view.
    private(set) var splitDropSide: SplitSide?
    /// The page area, which takes tabs dropped on it into a split view.
    @ObservationIgnored var contentFrame: CGRect?

    /// The space whose dot is being dragged along the switcher to reorder it.
    private(set) var draggedSpaceID: Space.ID?

    /// Points per second the list scrolls while the pointer rests near its top or bottom edge,
    /// so a tab can reach rows scrolled out of view; negative scrolls up.
    @ObservationIgnored private(set) var autoscrollSpeed: CGFloat = 0
    /// Observed apart from the speed, so the list starts and stops scrolling without
    /// re-rendering on every pointer move.
    private(set) var isAutoscrolling = false

    var isDragging: Bool { draggedTabID != nil }

    /// Reorders live, like tabs within a section: the dot takes the slot of the dots the pointer passed.
    func drag(_ space: Space, to location: CGPoint, in browser: Browser) {
        draggedSpaceID = space.id
        let index = browser.spaces.filter { other in
            other.id != space.id && (spaceDotFrames[other.id]?.midX ?? .infinity) < location.x
        }.count
        withAnimation(.snappy(duration: 0.2)) { browser.moveSpace(space, to: index) }
    }

    /// Also called when the gesture is cancelled.
    func endSpaceDrag() {
        draggedSpaceID = nil
    }

    func drag(_ tab: Tab, to location: CGPoint, in browser: Browser) {
        if draggedTabID != tab.id {
            let frame = tabFrames[tab.id] ?? CGRect(origin: location, size: .zero)
            grabOffset = CGSize(width: location.x - frame.midX, height: location.y - frame.midY)
            draggedTabID = tab.id
        }
        self.location = location
        updateAutoscroll()

        if let contentFrame, contentFrame.contains(location) {
            setPendingDestination(nil)
            isOverSpaceSwitcher = false
            hoveredSpaceID = nil
            let side: SplitSide = location.x < contentFrame.midX ? .leading : .trailing
            let target = browser.tabKept(droppingTab: tab, on: side) == nil ? nil : side
            if target != splitDropSide {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { splitDropSide = target }
            }
            return
        }
        if splitDropSide != nil {
            withAnimation(.snappy(duration: 0.2)) { splitDropSide = nil }
        }

        guard let source = browser.position(of: tab) else {
            setPendingDestination(nil)
            return
        }
        if updateSpaceHover(source: source, at: location, in: browser) {
            setPendingDestination(nil)
            return
        }
        if !showsDropZones, hasLeftUpwards(source.section, at: location) {
            withAnimation(.snappy(duration: 0.22)) { showsDropZones = true }
        }
        guard let destination = destination(for: tab, at: location, in: browser) else {
            setPendingDestination(nil)
            return
        }
        if destination.section == source.section {
            setPendingDestination(nil)
            if destination != source {
                withAnimation(.snappy(duration: 0.2)) { browser.moveTab(tab, to: destination) }
            }
        } else {
            setPendingDestination(destination)
        }
    }

    /// Advances the auto-scroll by `elapsed` seconds and returns the list's new offset, or `nil`
    /// once it can't scroll further that way.
    func autoscroll(by elapsed: Double, in browser: Browser) -> CGFloat? {
        // The previous step moved the rows under the resting pointer, which may now aim at another slot.
        if let tab = browser.allTabs.first(where: { $0.id == draggedTabID }) {
            drag(tab, to: location, in: browser)
        }
        guard isAutoscrolling, let range = listScrollRanges[browser.activeSpaceID] else { return nil }
        let offset = min(max(range.offset + autoscrollSpeed * elapsed, 0), range.maxOffset)
        guard offset != range.offset else { return nil }
        // Ahead of the scroll view's report, so the next step continues from here.
        listScrollRanges[browser.activeSpaceID]?.offset = offset
        return offset
    }

    /// The section's tabs, with the slot a tab dragged in from another section will drop into.
    func items(_ tabs: [Tab], in section: TabSection) -> [SidebarDragItem] {
        var items = tabs.map(SidebarDragItem.tab)
        if let pendingDestination, pendingDestination.section == section {
            items.insert(.slot, at: min(pendingDestination.index, items.count))
        }
        return items
    }

    func drop(_ tab: Tab, at location: CGPoint, in browser: Browser) {
        let isOverSpaceSwitcher = isOverSpaceSwitcher
        let splitDropSide = splitDropSide
        let isOverContent = contentFrame?.contains(location) ?? false
        let targetSpace = browser.spaces.first { $0.id == hoveredSpaceID && $0.id != browser.activeSpaceID }
        // Where the slot shows, which the pointer may have just left on release.
        let pendingDestination = pendingDestination
        // End first: a view inserted while it is still dimmed as the drag placeholder
        // can keep that opacity once the insertion animation runs.
        endDrag()
        if let splitDropSide, let kept = browser.tabKept(droppingTab: tab, on: splitDropSide) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                browser.splitView(kept, with: tab, on: splitDropSide)
            }
        } else if isOverContent {
            // Missing the page's split targets doesn't fall through to the sections behind it.
        } else if isOverSpaceSwitcher {
            if let targetSpace {
                withAnimation(.snappy(duration: 0.25)) { browser.moveTab(tab, to: targetSpace) }
            }
        } else if let pendingDestination {
            withAnimation(.snappy(duration: 0.25)) { browser.moveTab(tab, to: pendingDestination) }
        }
    }

    /// Also called when the gesture is cancelled, so it must be idempotent.
    func endDrag() {
        guard isDragging else { return }
        withAnimation(.snappy(duration: 0.2)) {
            draggedTabID = nil
            pendingDestination = nil
            showsDropZones = false
            hoveredSpaceID = nil
            splitDropSide = nil
        }
        isOverSpaceSwitcher = false
        autoscrollSpeed = 0
        isAutoscrolling = false
    }

    /// The slot opening slides the rows below it, as a reorder within the section does.
    private func setPendingDestination(_ destination: TabPosition?) {
        guard destination != pendingDestination else { return }
        withAnimation(.snappy(duration: 0.2)) { pendingDestination = destination }
    }

    /// Scrolls faster the deeper the pointer is in the edge band, from a crawl to 800 pt/s.
    private func updateAutoscroll() {
        let band: CGFloat = 32
        var speed: CGFloat = 0
        if let viewport = scrollViewportFrame, viewport.height > band * 2,
           (viewport.minX...viewport.maxX).contains(location.x),
           (viewport.minY...viewport.maxY).contains(location.y) {
            let upward = (viewport.minY + band - location.y) / band
            let downward = (location.y - (viewport.maxY - band)) / band
            let depth = max(upward, downward)
            if depth > 0 {
                speed = (80 + 720 * min(depth, 1) * min(depth, 1)) * (upward > 0 ? -1 : 1)
            }
        }
        autoscrollSpeed = speed
        if isAutoscrolling != (speed != 0) { isAutoscrolling = speed != 0 }
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
        if let pinnedAreaFrame, visible(pinnedAreaFrame).insetBy(dx: 0, dy: -6).contains(location) {
            return TabPosition(section: .pinned, index: listIndex(at: location, in: browser.pinnedTabs, excluding: tab))
        }
        if let todayAreaFrame, location.y >= visible(todayAreaFrame).minY - 6 {
            return TabPosition(section: .today, index: listIndex(at: location, in: browser.todayTabs, excluding: tab))
        }
        return nil
    }

    /// The part of a section the list shows: above the list are the space's name and the
    /// favorites, which a section scrolled under them mustn't claim.
    private func visible(_ sectionFrame: CGRect) -> CGRect {
        scrollViewportFrame.map(sectionFrame.intersection) ?? sectionFrame
    }

    private func listIndex(at location: CGPoint, in tabs: [Tab], excluding tab: Tab) -> Int {
        tabs.filter { $0.id != tab.id && (tabFrames[$0.id]?.midY ?? .infinity) < location.y }.count
    }
}

struct ListScrollRange: Equatable {
    var offset: CGFloat
    var maxOffset: CGFloat
}

/// A row of a section while a tab is dragged: one of its tabs, or the slot the dragged tab will drop into.
enum SidebarDragItem: Identifiable {
    case tab(Tab)
    case slot

    enum ID: Hashable {
        case tab(Tab.ID)
        case slot
    }

    var id: ID {
        switch self {
        case .tab(let tab): .tab(tab.id)
        case .slot: .slot
        }
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

/// The gap a tab dragged in from another section will drop into, sized like what it becomes there.
struct SidebarDropSlot: View {
    let isTile: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: isTile ? Theme.tileCornerRadius : Theme.rowCornerRadius, style: .continuous)
            .fill(Theme.hoverFill)
            .frame(maxWidth: .infinity)
            .frame(height: isTile ? Theme.tileHeight : Theme.tabRowHeight)
            .transition(.opacity)
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
