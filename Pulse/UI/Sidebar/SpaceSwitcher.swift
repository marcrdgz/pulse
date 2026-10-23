import AppKit
import SwiftUI

/// The bottom bar: one dot per space and a button to create a new one.
struct SpaceSwitcher: View {
    @Environment(Browser.self) private var browser
    @Environment(SidebarDragController.self) private var dragController

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(browser.spaces.enumerated()), id: \.element.id) { index, space in
                SpaceDot(space: space, isActive: space.id == browser.activeSpaceID)
                    .help(index < 9 ? "\(space.name) (⌃\(index + 1))" : space.name)
            }
            Spacer(minLength: 0)
            if !browser.downloads.downloads.isEmpty {
                DownloadsButton()
            }
            Button { browser.createSpace() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(SidebarIconButtonStyle())
            .help("New Space")
            .accessibilityLabel("New Space")
        }
        .frame(height: 28)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            dragController.spaceSwitcherFrame = frame
        }
        .animation(.snappy(duration: 0.2), value: browser.activeSpaceID)
    }
}

struct SpaceDot: View {
    @Environment(Browser.self) private var browser
    /// Absent in the collapsed sidebar, which has no tab dragging.
    @Environment(SidebarDragController.self) private var dragController: SidebarDragController?
    let space: Space
    let isActive: Bool

    var body: some View {
        let isHovered = dragController?.hoveredSpaceID == space.id
        let isProminent = isActive || isHovered
        Button { browser.selectSpace(space) } label: {
            Circle()
                .fill(Theme.swatch(space.theme))
                .frame(width: isProminent ? 10 : 7, height: isProminent ? 10 : 7)
                .opacity(isProminent ? 1 : 0.55)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            dragController?.spaceDotFrames[space.id] = frame
        }
        // Above the dot and starting at its leading edge, so it covers no other dot and stays in the window.
        .overlay(alignment: .bottomLeading) {
            if isHovered {
                Text(space.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    )
                    // The active space is no drop target.
                    .opacity(isActive ? 0.6 : 1)
                    .offset(y: -26)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .accessibilityLabel(space.name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .contextMenu { SpaceContextMenu(space: space) }
    }
}

/// Turns a horizontal two-finger swipe over the sidebar into one space switch per gesture.
final class SpaceSwipeTracker {
    private var horizontal: CGFloat = 0
    private var vertical: CGFloat = 0
    private var didSwitch = false

    /// Returns the space offset to move by, or `nil` while the gesture isn't a clear horizontal swipe.
    func offset(for event: NSEvent) -> Int? {
        guard event.hasPreciseScrollingDeltas else { return nil }
        switch event.phase {
        case .began:
            horizontal = 0
            vertical = 0
            didSwitch = false
            return nil
        case .changed:
            horizontal += event.scrollingDeltaX
            vertical += event.scrollingDeltaY
            guard !didSwitch, abs(horizontal) > 40, abs(horizontal) > abs(vertical) * 2 else { return nil }
            didSwitch = true
            // Fingers moving left reveal the space to the right, as in Arc.
            return horizontal < 0 ? 1 : -1
        default:
            return nil
        }
    }

    /// Whether the current gesture already switched spaces, so the rest of it should be swallowed.
    var isConsumingGesture: Bool { didSwitch }
}
