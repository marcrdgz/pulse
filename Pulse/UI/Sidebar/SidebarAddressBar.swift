import SwiftUI

/// Arc's compact address pill: shows the host and opens the command bar to edit the URL.
struct SidebarAddressBar: View {
    @Environment(Browser.self) private var browser
    @State private var isHovered = false

    var body: some View {
        let tab = browser.activeTab
        Button { browser.showCommandBar(.editActiveTab) } label: {
            HStack(spacing: 6) {
                if tab?.url.scheme == "https" {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .opacity(0.5)
                }
                Text(tab?.url.displayHost ?? "Search or Enter URL…")
                    .lineLimit(1)
                    .opacity(tab == nil ? 0.5 : 1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                    .fill(isHovered ? Theme.activeTabFill : Theme.pillFill)
            )
            .overlay(alignment: .bottom) {
                if let tab, tab.isLoading {
                    LoadingBar(progress: tab.estimatedProgress)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open Location (⌘L)")
    }
}

private struct LoadingBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.accentColor)
                .frame(width: proxy.size.width * max(progress, 0.05), height: 2)
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        .frame(height: 2)
        .padding(.horizontal, 8)
    }
}
