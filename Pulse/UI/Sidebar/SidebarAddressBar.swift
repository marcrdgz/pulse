import SwiftUI

/// Arc's compact address pill: shows the host and opens the command bar to edit the URL.
struct SidebarAddressBar: View {
    @Environment(Browser.self) private var browser
    @State private var isHovered = false
    @State private var isShowingSiteControls = false

    var body: some View {
        let tab = browser.activeTab
        Button { browser.showCommandBar(.editActiveTab) } label: {
            HStack(spacing: 6) {
                if tab?.url.scheme == "https" {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .opacity(0.5)
                }
                Text(tab?.internalPage?.url.absoluteString ?? tab?.url.displayHost ?? "Search or Enter URL…")
                    .lineLimit(1)
                    .opacity(tab == nil ? 0.5 : 1)
                Spacer(minLength: 0)
                if let tab, isAllowingAds(on: tab) {
                    Image(systemName: "shield.slash")
                        .font(.system(size: 11))
                        .opacity(0.5)
                        .help("Ads and trackers are allowed on this site")
                }
            }
            .font(.system(size: 13))
            .padding(.leading, 10)
            // Room for the site controls button, which sits over the pill rather than inside it.
            .padding(.trailing, tab?.url.isWebPage == true ? 30 : 10)
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
        .contextMenu {
            if let tab {
                Button("Edit URL…") { browser.showCommandBar(.editActiveTab) }
                Button("Copy URL") { browser.copyURL(of: tab) }
                ShareLink(item: tab.url)
                Divider()
                Button("Reload Page") { tab.reload() }
                if browser.contentBlocker.isEnabled, tab.url.isWebPage, let site = tab.url.displayHost {
                    Divider()
                    Button(isAllowingAds(on: tab) ? "Block Ads on \(site)" : "Allow Ads on \(site)") {
                        browser.toggleContentBlocking(on: tab)
                    }
                }
            }
        }
        .overlay(alignment: .trailing) {
            if let tab, tab.url.isWebPage {
                Button { isShowingSiteControls.toggle() } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                        .opacity(0.7)
                }
                .buttonStyle(SidebarIconButtonStyle(size: 24))
                .padding(.trailing, 4)
                .help("Site Controls")
                .popover(isPresented: $isShowingSiteControls, arrowEdge: .bottom) {
                    SiteControls(tab: tab)
                }
            }
        }
    }
}

extension SidebarAddressBar {
    /// Only worth showing while blocking is on: then it's the exception.
    private func isAllowingAds(on tab: Tab) -> Bool {
        browser.contentBlocker.isEnabled && tab.url.isWebPage && !browser.contentBlocker.isBlocking(on: tab.url)
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
