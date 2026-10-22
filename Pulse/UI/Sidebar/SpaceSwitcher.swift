import AppKit
import SwiftUI

/// The bottom bar: one dot per space and a button to create a new one.
struct SpaceSwitcher: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(browser.spaces.enumerated()), id: \.element.id) { index, space in
                SpaceDot(space: space, isActive: space.id == browser.activeSpaceID)
                    .help(index < 9 ? "\(space.name) (⌃\(index + 1))" : space.name)
            }
            Spacer(minLength: 0)
            Button { browser.createSpace() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(SidebarIconButtonStyle())
            .help("New Space")
        }
        .frame(height: 28)
        .animation(.snappy(duration: 0.2), value: browser.activeSpaceID)
    }
}

private struct SpaceDot: View {
    @Environment(Browser.self) private var browser
    let space: Space
    let isActive: Bool

    var body: some View {
        Button { browser.selectSpace(space) } label: {
            Circle()
                .fill(Theme.swatch(space.theme))
                .frame(width: isActive ? 10 : 7, height: isActive ? 10 : 7)
                .opacity(isActive ? 1 : 0.55)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
