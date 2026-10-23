import AppKit
import SwiftUI

/// One space's part of the sidebar: its name, pinned tabs and today tabs.
/// Every space is rendered side by side so switching can slide between them.
struct SpaceContent: View {
    @Environment(Browser.self) private var browser
    @Environment(SidebarDragController.self) private var dragController
    let space: Space
    /// Only the visible space reports frames to the drag controller.
    let isActive: Bool
    /// Per space: matched geometry ids must be unique among the views on screen.
    @Namespace private var activeHighlight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SpaceHeader(space: space)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    pinnedSection
                    Rectangle()
                        .fill(Theme.sidebarText.opacity(0.12))
                        .frame(height: 1)
                        .padding(.horizontal, 4)
                    NewTabButton()
                    todaySection
                }
            }
            .scrollIndicators(.never)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                if isActive { dragController.scrollViewportFrame = frame }
            }
        }
        .animation(.snappy(duration: 0.2), value: space.activeTabID)
    }

    @ViewBuilder private var pinnedSection: some View {
        let showsDropZone = isActive && dragController.showsDropZones && space.pinnedTabs.isEmpty
        VStack(spacing: 2) {
            if showsDropZone {
                SidebarDropZone(title: "Drop here to pin", isTargeted: dragController.pendingSection == .pinned)
            }
            ForEach(space.pinnedTabs) { tab in
                row(for: tab)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(isActive && dragController.pendingSection == .pinned && !showsDropZone ? Theme.hoverFill : .clear)
        )
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            // An empty section without a drop zone has no height and must not catch drops.
            if isActive { dragController.pinnedAreaFrame = frame.height > 0 ? frame : nil }
        }
        .animation(.snappy(duration: 0.22), value: space.pinnedTabs.map(\.id))
    }

    private var todaySection: some View {
        VStack(spacing: 2) {
            ForEach(space.todayTabs) { tab in
                row(for: tab)
            }
        }
        .frame(maxWidth: .infinity, minHeight: isActive && dragController.isDragging ? 44 : 0, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(isActive && dragController.pendingSection == .today ? Theme.hoverFill : .clear)
        )
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if isActive { dragController.todayAreaFrame = frame }
        }
        .animation(.snappy(duration: 0.22), value: space.todayTabs.map(\.id))
    }

    private func row(for tab: Tab) -> some View {
        TabRow(tab: tab, isActive: tab.id == space.activeTabID, highlightNamespace: activeHighlight)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
    }
}

/// The space's name above its pinned tabs; double-click to rename.
private struct SpaceHeader: View {
    @Environment(Browser.self) private var browser
    let space: Space
    @State private var draftName = ""
    @FocusState private var isNameFieldFocused: Bool

    private var isRenaming: Bool { browser.renamingSpaceID == space.id }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.swatch(space.theme))
                .frame(width: 8, height: 8)
            if isRenaming {
                TextField("Space Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($isNameFieldFocused)
                    .onAppear {
                        draftName = space.name
                        isNameFieldFocused = true
                    }
                    .onSubmit(commitRename)
                    .onExitCommand(perform: browser.endRenaming)
                    .onChange(of: isNameFieldFocused) {
                        if !isNameFieldFocused, isRenaming { commitRename() }
                    }
            } else {
                Text(space.name)
                    .lineLimit(1)
                    .opacity(0.75)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { browser.beginRenaming(space) }
        .contextMenu { SpaceContextMenu(space: space) }
    }

    private func commitRename() {
        browser.rename(space, to: draftName)
        browser.endRenaming()
    }
}

struct SpaceContextMenu: View {
    @Environment(Browser.self) private var browser
    let space: Space

    var body: some View {
        Button("Rename Space…") { browser.beginRenaming(space) }
        Picker("Color", selection: Binding(get: { space.theme }, set: { browser.setTheme($0, for: space) })) {
            ForEach(SpaceTheme.allCases, id: \.self) { theme in
                Text(theme.displayName).tag(theme)
            }
        }
        Divider()
        Button("Close Today Tabs") { browser.closeTodayTabs(in: space) }
            .disabled(space.todayTabs.isEmpty)
        Button("New Space") { browser.createSpace() }
        Divider()
        Button("Delete Space…", action: confirmDelete)
            .disabled(browser.spaces.count < 2)
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete “\(space.name)”?"
        alert.informativeText = "Its pinned and today tabs will be closed. Favorites are kept."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            browser.delete(space)
        }
    }
}
