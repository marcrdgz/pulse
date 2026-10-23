import AppKit
import SwiftUI

struct BrowserWindow: View {
    @Environment(Browser.self) private var browser
    @AppStorage("sidebarWidth") private var sidebarWidth = Theme.defaultSidebarWidth
    @State private var isPeekingSidebar = false
    @State private var peekTask: Task<Void, Never>?
    @State private var controlShortcutMonitor: Any?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            // Cross-fades between spaces' themes; gradients don't interpolate their colors.
            Theme.sidebarGradient(browser.activeSpace.theme)
                .id(browser.activeSpace.theme)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.35), value: browser.activeSpace.theme)
            WindowDragArea()

            HStack(spacing: 0) {
                if browser.isSidebarExpanded {
                    SidebarView()
                        .frame(width: sidebarWidth)
                        .overlay(alignment: .trailing) {
                            SidebarResizeHandle(width: $sidebarWidth)
                        }
                        .transition(reduceMotion ? .opacity : .move(edge: .leading))
                } else {
                    CollapsedSidebar()
                        .onHover(perform: schedulePeek)
                        .transition(.opacity)
                }
                content
            }

            if isPeekingSidebar {
                sidebarPeek
            }

            if let mode = browser.commandBar {
                commandBar(mode)
            }

            if let toast = browser.toast {
                ToastView(message: toast)
                    .transition(.slide(from: .bottom, reduceMotion: reduceMotion))
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 720, minHeight: 460)
        .background(WindowChrome(showsTrafficLights: browser.isSidebarExpanded || isPeekingSidebar))
        .animation(.snappy(duration: 0.25), value: browser.isSidebarExpanded)
        .animation(.snappy(duration: 0.2), value: isPeekingSidebar)
        .onChange(of: browser.isSidebarExpanded) {
            peekTask?.cancel()
            isPeekingSidebar = false
        }
        .animation(.easeOut(duration: 0.15), value: browser.commandBar)
        .animation(.snappy, value: browser.toast)
        .animation(.snappy(duration: 0.2), value: browser.isFindBarVisible)
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
    }

    @ViewBuilder private var page: some View {
        if let tab = browser.activeTab, tab.internalPage == .history {
            HistoryPage(tab: tab)
                .id(tab.id)
        } else if browser.activeTab?.internalPage == .downloads {
            DownloadsPage()
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
                            .transition(.slide(from: .top, reduceMotion: reduceMotion))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let request = browser.activePermissionRequest {
                        PermissionPrompt(request: request)
                            .padding(12)
                            .transition(.slide(from: .top, reduceMotion: reduceMotion))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let link = tab.hoveredLink {
                        LinkPreview(link: link)
                            .transition(.opacity)
                    }
                }
                .animation(.snappy(duration: 0.2), value: browser.activePermissionRequest?.id)
                .animation(.easeOut(duration: 0.12), value: tab.hoveredLink == nil)
        } else {
            EmptyStateView()
        }
    }

    /// Hovering the collapsed rail slides the full sidebar in over the page, like Arc.
    private var sidebarPeek: some View {
        SidebarView()
            .frame(width: sidebarWidth)
            .background(Theme.sidebarGradient(browser.activeSpace.theme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.contentCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, x: 2)
            .padding(.vertical, Theme.contentInset)
            .onHover { if !$0 { isPeekingSidebar = false } }
            .transition(.slide(from: .leading, reduceMotion: reduceMotion))
    }

    private func schedulePeek(isHovering: Bool) {
        peekTask?.cancel()
        guard isHovering else { return }
        // Long enough that pointing at a rail icon to click it doesn't pop the sidebar open.
        peekTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { isPeekingSidebar = true }
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
            .transition(reduceMotion ? .opacity : .scale(scale: 0.97, anchor: .top).combined(with: .opacity))
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
    }
}

/// The hovered link's URL in the page's bottom-left corner, like Chrome's status bubble.
private struct LinkPreview: View {
    let link: String

    var body: some View {
        Text(link)
            .font(.system(size: 11))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.primary.opacity(0.1))
            )
            .frame(maxWidth: 480, alignment: .leading)
            .padding(6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Window tweaks SwiftUI doesn't expose: drag-from-sidebar and hiding traffic lights with the sidebar.
/// The browser's own window, so commands can tell it apart from Settings or panels.
enum BrowserWindowReference {
    static weak var window: NSWindow?

    /// Whether ⌘W should close the frontmost window instead of a tab.
    static var isOtherWindowKey: Bool {
        guard let keyWindow = NSApp.keyWindow else { return false }
        return keyWindow !== window
    }
}

private struct WindowChrome: NSViewRepresentable {
    let showsTrafficLights: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // The view is attached to its window only after this pass.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            BrowserWindowReference.window = window
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
