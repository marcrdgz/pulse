import SwiftUI

struct SidebarView: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarToolbar()
            SidebarAddressBar()
            if !browser.pinnedTabs.isEmpty {
                PinnedTabsGrid()
            }
            Rectangle()
                .fill(Theme.sidebarText.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 4)
            NewTabButton()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(browser.todayTabs) { tab in
                        TabRow(tab: tab)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .foregroundStyle(Theme.sidebarText)
    }
}

/// The row the traffic lights live in, with Arc's navigation buttons on the right.
private struct SidebarToolbar: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        let tab = browser.activeTab
        HStack(spacing: 2) {
            Spacer()
            Button(action: browser.toggleSidebar) {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar (⌘S)")
            Button { tab?.goBack() } label: {
                Image(systemName: "arrow.left")
            }
            .disabled(!(tab?.canGoBack ?? false))
            .help("Back (⌘[)")
            Button { tab?.goForward() } label: {
                Image(systemName: "arrow.right")
            }
            .disabled(!(tab?.canGoForward ?? false))
            .help("Forward (⌘])")
            Button {
                if tab?.isLoading == true { tab?.stopLoading() } else { tab?.reload() }
            } label: {
                Image(systemName: tab?.isLoading == true ? "xmark" : "arrow.clockwise")
            }
            .disabled(tab == nil)
            .help("Reload (⌘R)")
        }
        .font(.system(size: 13, weight: .medium))
        .buttonStyle(SidebarIconButtonStyle())
        .frame(height: 30)
        // Leave room for the window's traffic lights.
        .padding(.leading, 70)
    }
}
