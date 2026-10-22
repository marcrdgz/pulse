import SwiftUI

struct TabRow: View {
    @Environment(Browser.self) private var browser
    let tab: Tab
    /// The space's own active tab, so inactive spaces keep their highlight while sliding by.
    let isActive: Bool
    /// Shared by a space's rows so the active highlight slides between them.
    let highlightNamespace: Namespace.ID
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @FocusState private var isTitleFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(tab: tab, size: 16)
            if isRenaming {
                TextField("Tab Name", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($isTitleFieldFocused)
                    .onAppear { isTitleFieldFocused = true }
                    .onSubmit(commitRename)
                    .onExitCommand { isRenaming = false }
                    .onChange(of: isTitleFieldFocused) {
                        if !isTitleFieldFocused, isRenaming { commitRename() }
                    }
            } else {
                Text(tab.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if isHovered, !isRenaming {
                Button { browser.close(tab) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(SidebarIconButtonStyle())
                .help("Close Tab (⌘W)")
            }
        }
        .font(.system(size: 13, weight: isActive ? .medium : .regular))
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background { background }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { browser.select(tab) }
        .simultaneousGesture(TapGesture(count: 2).onEnded(startRenaming))
        .contextMenu { TabContextMenu(tab: tab, onRename: startRenaming) }
        .sidebarDraggable(tab)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
        if isActive {
            shape
                .fill(Theme.activeTabFill)
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                .matchedGeometryEffect(id: "activeTabHighlight", in: highlightNamespace)
        } else if isHovered {
            shape.fill(Theme.hoverFill)
        }
    }

    private func startRenaming() {
        draftTitle = tab.displayTitle
        isRenaming = true
    }

    private func commitRename() {
        isRenaming = false
        browser.rename(tab, to: draftTitle)
    }
}

struct TabContextMenu: View {
    @Environment(Browser.self) private var browser
    let tab: Tab
    var onRename: (() -> Void)?

    var body: some View {
        let section = browser.position(of: tab)?.section
        Button(section == .favorites ? "Remove from Favorites" : "Add to Favorites") { browser.toggleFavorite(tab) }
        Button(section == .pinned ? "Unpin Tab" : "Pin Tab") { browser.togglePin(tab) }
        let otherSpaces = browser.spaces.filter { !$0.contains(tab) }
        if section != .favorites, !otherSpaces.isEmpty {
            Menu("Move to Space") {
                ForEach(otherSpaces) { space in
                    Button(space.name) { browser.moveTab(tab, to: space) }
                }
            }
        }
        if let onRename {
            Button("Rename Tab…", action: onRename)
        }
        Button("Copy URL") { browser.copyURL(of: tab) }
        Divider()
        Button(tab.isPinned ? "Reset Pinned Tab" : "Close Tab") { browser.close(tab) }
    }
}

struct FaviconView: View {
    let tab: Tab
    let size: CGFloat

    var body: some View {
        Group {
            if let page = tab.internalPage {
                Image(systemName: page.symbol)
                    .resizable()
                    .scaledToFit()
            } else if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: size / 5, style: .continuous))
            } else if tab.isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .opacity(0.6)
            }
        }
        .frame(width: size, height: size)
    }
}
