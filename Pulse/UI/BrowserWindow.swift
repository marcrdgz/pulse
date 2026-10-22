import AppKit
import SwiftUI

struct BrowserWindow: View {
    @Environment(Browser.self) private var browser
    @AppStorage("sidebarWidth") private var sidebarWidth = Theme.defaultSidebarWidth
    @State private var isPeekingSidebar = false
    @State private var peekTask: Task<Void, Never>?
    @State private var controlShortcutMonitor: Any?

    var body: some View {
        ZStack(alignment: .leading) {
            // Cross-fades between spaces' themes; gradients don't interpolate their colors.
            Theme.sidebarGradient(browser.activeSpace.theme)
                .id(browser.activeSpace.theme)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.35), value: browser.activeSpace.theme)
            WindowDragArea()

            HStack(spacing: 0) {
                if browser.isSidebarVisible {
                    SidebarView()
                        .frame(width: sidebarWidth)
                        .overlay(alignment: .trailing) {
                            SidebarResizeHandle(width: $sidebarWidth)
                        }
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
        .animation(.snappy(duration: 0.2), value: browser.isFindBarVisible)
        .onChange(of: browser.isSidebarVisible) { isPeekingSidebar = false }
        .onAppear(perform: installControlShortcutMonitor)
        .sheet(isPresented: Bindable(browser).isClearBrowsingDataPresented) {
            ClearBrowsingDataView()
                .environment(browser)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            browser.saveSession()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            DefaultBrowserBanner()
            page
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.contentCornerRadius, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: Theme.contentCornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        )
        .padding(.vertical, Theme.contentInset)
        .padding(.trailing, Theme.contentInset)
        .padding(.leading, browser.isSidebarVisible ? 0 : Theme.contentInset)
    }

    @ViewBuilder private var page: some View {
        if let tab = browser.activeTab, tab.internalPage == .history {
            HistoryPage(tab: tab)
                .id(tab.id)
        } else if let tab = browser.activeTab {
            WebView(tab: tab)
                .overlay {
                    if let error = tab.loadError {
                        LoadErrorView(tab: tab, error: error)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if browser.isFindBarVisible {
                        FindBar()
                            .padding(12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let request = browser.activePermissionRequest {
                        PermissionPrompt(request: request)
                            .padding(12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.2), value: browser.activePermissionRequest?.id)
        } else {
            EmptyStateView()
        }
    }

    /// With the sidebar hidden, hovering the window's left edge slides it in over the page, like Arc.
    @ViewBuilder private var sidebarPeek: some View {
        Color.clear
            .frame(width: Theme.contentInset)
            .contentShape(Rectangle())
            .onHover { isHovering in
                peekTask?.cancel()
                guard isHovering else { return }
                // A short delay so sweeping the pointer past the edge doesn't pop the sidebar open.
                peekTask = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    if !Task.isCancelled { isPeekingSidebar = true }
                }
            }

        if isPeekingSidebar {
            SidebarView()
                .frame(width: sidebarWidth)
                .background(Theme.sidebarGradient(browser.activeSpace.theme))
                .clipShape(RoundedRectangle(cornerRadius: Theme.contentCornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 12, x: 2)
                .padding(.vertical, Theme.contentInset)
                .onHover { if !$0 { isPeekingSidebar = false } }
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    /// ⌃⇥ and ⌃1…⌃9 never reach the menu: the key view loop and WKWebView consume them first.
    private func installControlShortcutMonitor() {
        guard controlShortcutMonitor == nil else { return }
        controlShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 48, modifiers.subtracting(.shift) == .control {
                browser.selectAdjacentTab(offset: modifiers.contains(.shift) ? -1 : 1)
                return nil
            }
            if modifiers == .control, let number = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(number) {
                browser.selectSpace(number: number)
                return nil
            }
            return event
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
            window.isMovableByWindowBackground = false
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = !showsTrafficLights
            }
        }
    }
}

/// Drag the sidebar's trailing edge to resize it; the width is remembered across launches.
private struct SidebarResizeHandle: View {
    @Binding var width: Double
    @State private var widthAtDragStart: Double?

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let start = widthAtDragStart ?? width
                        widthAtDragStart = start
                        let range = Theme.sidebarWidthRange
                        width = min(max(start + value.translation.width, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in widthAtDragStart = nil }
            )
    }
}
