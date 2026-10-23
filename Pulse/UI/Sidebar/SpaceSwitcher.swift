import AppKit
import SwiftUI

/// The bottom bar, laid out like Arc's: downloads on the left, the spaces centered and the
/// new-item menu on the right.
struct SpaceSwitcher: View {
    @Environment(Browser.self) private var browser
    @Environment(SidebarDragController.self) private var dragController

    var body: some View {
        let draft = browser.spaceDraft
        HStack(spacing: 0) {
            // Equal widths on both ends keep the spaces centered in the sidebar.
            Group {
                if draft == nil { DownloadsButton() }
            }
            .frame(width: Self.edgeWidth, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(Array(browser.spaces.enumerated()), id: \.element.id) { index, space in
                    SpaceDot(space: space, isActive: draft == nil && space.id == browser.activeSpaceID)
                        .help(index < 9 ? "\(space.name) (⌃\(index + 1))" : space.name)
                }
                if let draft {
                    SpaceIcon(space: draft, size: SpaceDot.prominentSize(for: draft))
                        .frame(width: Theme.bottomBarButtonSize, height: Theme.bottomBarButtonSize)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Spacer(minLength: 0)
            Group {
                if draft == nil { NewItemButton() }
            }
            .frame(width: Self.edgeWidth, alignment: .trailing)
        }
        .frame(height: 34)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            dragController.spaceSwitcherFrame = frame
        }
        .animation(.snappy(duration: 0.2), value: browser.activeSpaceID)
        .animation(.snappy(duration: 0.2), value: draft == nil)
    }

    private static let edgeWidth = Theme.bottomBarButtonSize
}

/// Arc's "+" at the bottom right: a small menu of things to create, with the button turning into
/// a close button while it's open.
private struct NewItemButton: View {
    @Environment(Browser.self) private var browser
    @State private var isMenuPresented = false

    var body: some View {
        Button { isMenuPresented.toggle() } label: {
            Image(systemName: isMenuPresented ? "xmark" : "plus")
                .font(.system(size: 16, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(SidebarIconButtonStyle(size: Theme.bottomBarButtonSize))
        .help("New Tab or Space")
        .accessibilityLabel("New Tab or Space")
        .popover(isPresented: $isMenuPresented, arrowEdge: .top) {
            VStack(spacing: 0) {
                NewItemRow(title: "New Space", symbol: "plus.square.on.square") {
                    isMenuPresented = false
                    browser.beginCreatingSpace()
                }
                Divider()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                NewItemRow(title: "New Tab", symbol: "plus.square", shortcut: "⌘T") {
                    isMenuPresented = false
                    browser.showCommandBar(.newTab)
                }
            }
            .padding(8)
            .frame(width: 220)
        }
    }
}

private struct NewItemRow: View {
    let title: String
    let symbol: String
    var shortcut: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(isHovered ? 0.18 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct SpaceDot: View {
    @Environment(Browser.self) private var browser
    /// Absent in the collapsed sidebar, which has no tab or space dragging.
    @Environment(SidebarDragController.self) private var dragController: SidebarDragController?
    @GestureState private var isReordering = false
    let space: Space
    let isActive: Bool

    var body: some View {
        let isHovered = dragController?.hoveredSpaceID == space.id
        let isProminent = isActive || isHovered || dragController?.draggedSpaceID == space.id
        Button { browser.selectSpace(space) } label: {
            SpaceIcon(space: space, size: isProminent ? Self.prominentSize(for: space) : Self.restingSize(for: space))
                // Arc keeps emojis one size and mutes the inactive ones instead.
                .grayscale(isProminent ? 0 : 1)
                .opacity(isProminent ? 1 : space.icon == nil ? 0.55 : 0.8)
        }
        .buttonStyle(SidebarIconButtonStyle(size: Theme.bottomBarButtonSize))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            dragController?.spaceDotFrames[space.id] = frame
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .updating($isReordering) { _, isActive, _ in isActive = true }
                .onChanged { dragController?.drag(space, to: $0.location, in: browser) }
        )
        .onChange(of: isReordering) {
            if !isReordering { dragController?.endSpaceDrag() }
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
                    .offset(y: -Theme.bottomBarButtonSize - 4)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .accessibilityLabel(space.name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        // Only in the full sidebar: while it peeks over the collapsed rail, both show this dot.
        .popover(isPresented: isIconPickerPresented, arrowEdge: .top) {
            SpaceIconPicker(space: space)
                .environment(browser)
        }
        .contextMenu { SpaceContextMenu(space: space, canChangeIcon: dragController != nil) }
    }

    /// `SpaceIcon` sizes: a dot grows when prominent, an emoji (drawn 4pt larger) stays at Arc's 16pt.
    static func prominentSize(for space: Space) -> CGFloat {
        space.icon == nil ? 10 : 12
    }

    private static func restingSize(for space: Space) -> CGFloat {
        space.icon == nil ? 7 : 12
    }

    private var isIconPickerPresented: Binding<Bool> {
        Binding(
            get: { dragController != nil && browser.editingIconSpaceID == space.id },
            set: { if !$0 { browser.endEditingIcon() } }
        )
    }
}

/// A space's emoji, or its color dot when it has none.
struct SpaceIcon: View {
    let space: Space
    /// The dot's diameter; an emoji is drawn a little larger to read at the same weight.
    let size: CGFloat

    var body: some View {
        if let icon = space.icon {
            Text(icon)
                .font(.system(size: size + 4))
                .fixedSize()
        } else {
            Circle()
                .fill(Theme.swatch(space.theme))
                .frame(width: size, height: size)
        }
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
