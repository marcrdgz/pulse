import SwiftUI

/// A slim bar atop each split view pane, so either page can be navigated, read or closed
/// without first focusing it. The sidebar's controls only reach the focused pane.
/// It takes the page's color, like Safari's compact tabs, so it reads as part of the page.
struct SplitPaneBar: View {
    static let height: CGFloat = 24
    @Environment(Browser.self) private var browser
    let tab: Tab
    let isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    /// `nil` until the page has one, or when it can't be read as a plain opaque color: a
    /// translucent one would show the card through it and misjudge the page's lightness.
    private var pageColor: NSColor? {
        tab.pageColor?.usingColorSpace(.sRGB).flatMap { $0.alphaComponent > 0.9 ? $0 : nil }
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: tab.goBack) { Image(systemName: "arrow.left") }
                .accessibilityLabel("Back")
                .disabled(!tab.canGoBack)
                .help("Back")
            Button(action: tab.goForward) { Image(systemName: "arrow.right") }
                .accessibilityLabel("Forward")
                .disabled(!tab.canGoForward)
                .help("Forward")
            Button {
                if tab.isLoading { tab.stopLoading() } else { tab.reload() }
            } label: {
                Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
            }
            .accessibilityLabel(tab.isLoading ? "Stop" : "Reload")
            .help(tab.isLoading ? "Stop" : "Reload")

            address
                .frame(maxWidth: .infinity)

            Menu {
                Button("Copy URL") { browser.copyURL(of: tab) }
                Button("Separate Split View") { browser.separate(tab) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
            .help("More")
            Button { browser.close(tab) } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Close Pane")
                .help("Close Pane")
        }
        .font(.system(size: 10, weight: .medium))
        .buttonStyle(SidebarIconButtonStyle(size: 20))
        // The unfocused pane's bar steps back, so it's clear which page the keyboard reaches.
        .opacity(isFocused ? 1 : 0.55)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .padding(.horizontal, 4)
        .frame(height: Self.height)
        .background(Color(nsColor: pageColor ?? .windowBackgroundColor))
        // Icons and hover fills follow the page's lightness, not the system appearance.
        .environment(\.colorScheme, pageColor.map { $0.isDark ? .dark : .light } ?? colorScheme)
        .animation(.easeOut(duration: 0.2), value: pageColor)
        .simultaneousGesture(TapGesture().onEnded { browser.focusPane(of: tab) })
    }

    /// Opens the command bar on this pane's URL, as ⌘L does for the focused one.
    private var address: some View {
        Button {
            browser.focusPane(of: tab)
            browser.showCommandBar(.editActiveTab)
        } label: {
            HStack(spacing: 4) {
                if tab.url.scheme == "https" {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7))
                        .opacity(0.5)
                }
                Text(tab.internalPage?.url.absoluteString ?? tab.url.displayHost ?? tab.displayTitle)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
        }
        .help("Edit URL")
    }
}

private extension NSColor {
    /// Relative luminance below the midpoint, in sRGB.
    var isDark: Bool {
        0.2126 * redComponent + 0.7152 * greenComponent + 0.0722 * blueComponent < 0.5
    }
}
