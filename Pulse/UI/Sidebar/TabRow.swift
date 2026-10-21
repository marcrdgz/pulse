import SwiftUI

struct TabRow: View {
    @Environment(Browser.self) private var browser
    let tab: Tab
    @State private var isHovered = false

    private var isActive: Bool { tab.id == browser.activeTabID }

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(tab: tab, size: 16)
            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if isHovered {
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
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(isActive ? Theme.activeTabFill : isHovered ? Theme.hoverFill : .clear)
                .shadow(color: .black.opacity(isActive ? 0.08 : 0), radius: 1, y: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { browser.select(tab) }
        .contextMenu { TabContextMenu(tab: tab) }
    }
}

struct TabContextMenu: View {
    @Environment(Browser.self) private var browser
    let tab: Tab

    var body: some View {
        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { browser.togglePin(tab) }
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
            if let favicon = tab.favicon {
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
