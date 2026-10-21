import AppKit
import SwiftUI

struct BrowserWindow: View {
    @Environment(Browser.self) private var browser
    @State private var isPeekingSidebar = false

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.sidebarGradient

            HStack(spacing: 0) {
                if browser.isSidebarVisible {
                    SidebarView()
                        .frame(width: Theme.sidebarWidth)
                        .transition(.move(edge: .leading))
                }
                content
            }

            if !browser.isSidebarVisible {
                sidebarPeek
            }

            if let mode = browser.commandBar {
                commandBar(mode)
            }

            if let toast = browser.toast {
                ToastView(message: toast)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 720, minHeight: 460)
        .background(WindowChrome(showsTrafficLights: browser.isSidebarVisible || isPeekingSidebar))
        .animation(.snappy(duration: 0.25), value: browser.isSidebarVisible)
        .animation(.snappy(duration: 0.2), value: isPeekingSidebar)
        .animation(.easeOut(duration: 0.15), value: browser.commandBar)
        .animation(.snappy, value: browser.toast)
        .onChange(of: browser.isSidebarVisible) { isPeekingSidebar = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            browser.saveSession()
        }
    }

    private var content: some View {
        Group {
            if let tab = browser.activeTab {
                WebView(tab: tab)
            } else {
                EmptyStateView()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.contentCornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        )
        .padding(.vertical, Theme.contentInset)
        .padding(.trailing, Theme.contentInset)
        .padding(.leading, browser.isSidebarVisible ? 0 : Theme.contentInset)
    }

    /// With the sidebar hidden, hovering the window's left edge slides it in over the page, like Arc.
    @ViewBuilder private var sidebarPeek: some View {
        Color.clear
            .frame(width: Theme.contentInset)
            .contentShape(Rectangle())
            .onHover { if $0 { isPeekingSidebar = true } }

        if isPeekingSidebar {
            SidebarView()
                .frame(width: Theme.sidebarWidth)
                .background(Theme.sidebarGradient)
                .clipShape(RoundedRectangle(cornerRadius: Theme.contentCornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 12, x: 2)
                .padding(.vertical, Theme.contentInset)
                .onHover { if !$0 { isPeekingSidebar = false } }
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    private func commandBar(_ mode: CommandBarMode) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .onTapGesture(perform: browser.dismissCommandBar)
            CommandBarView(
                mode: mode,
                initialQuery: mode == .editActiveTab ? browser.activeTab?.url.absoluteString ?? "" : ""
            )
            .id(mode)
            .padding(.top, 120)
        }
        .transition(.opacity)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
            Text("Press ⌘T to open a new tab")
                .font(.system(size: 14))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 28)
            .allowsHitTesting(false)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Window tweaks SwiftUI doesn't expose: drag-from-sidebar and hiding traffic lights with the sidebar.
private struct WindowChrome: NSViewRepresentable {
    let showsTrafficLights: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // The view is attached to its window only after this pass.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = !showsTrafficLights
            }
        }
    }
}
