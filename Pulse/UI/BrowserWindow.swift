import AppKit
import SwiftUI

struct BrowserWindow: View {
    @Environment(Browser.self) private var browser
    @AppStorage("sidebarWidth") private var sidebarWidth = Theme.defaultSidebarWidth
    @State private var isPeekingSidebar = false
    @State private var peekTask: Task<Void, Never>?
    /// Set the update before Peek expands, so its card leaves without the closing transition.
    @State private var isExpandingPeek = false
    @State private var shortcutMonitor: Any?
    /// Shared by the sidebar and the page, which takes tabs dragged onto it into a split view.
    @State private var dragController = SidebarDragController()
    /// Shared by the sidebar, which the swipe drags, and the window background, whose color follows it.
    @State private var swipeTracker = SpaceSwipeTracker()
    /// The panes of the split last on screen, to tell a split closing from a switch to another tab.
    @State private var lastSplitTabIDs: Set<UUID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            SpaceBackground()
                .environment(swipeTracker)
            WindowDragArea()

            HStack(spacing: 0) {
                if browser.isSidebarExpanded {
                    SidebarView()
                        .environment(dragController)
                        .environment(swipeTracker)
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
                    .overlay {
                        if let peek = browser.peek {
                            peekOverlay(peek)
                        }
                    }
            }

            if isPeekingSidebar {
                sidebarPeek
            }

            // Above the page's web views, which would otherwise hide it.
            DragGhostLayer()
                .environment(dragController)

            if let mode = browser.commandBar {
                commandBar(mode)
            }

            if let toast = browser.toast {
                ToastView(toast: toast, theme: browser.activeSpace.theme, onHover: browser.setToastHovered)
                    .transition(.slide(from: .top, reduceMotion: reduceMotion))
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 720, minHeight: 460)
        .background(WindowChrome(browser: browser, showsTrafficLights: browser.isSidebarExpanded || isPeekingSidebar))
        .animation(.snappy(duration: 0.25), value: browser.isSidebarExpanded)
        .animation(.snappy(duration: 0.2), value: isPeekingSidebar)
        .onChange(of: browser.isSidebarExpanded) {
            peekTask?.cancel()
            isPeekingSidebar = false
        }
        .onChange(of: browser.commandBar) { _, mode in
            if mode == nil { focusPageAfterCommandBar() }
        }
        .animation(.easeOut(duration: 0.15), value: browser.commandBar)
        .animation(.snappy(duration: 0.25), value: browser.peek?.id)
        .animation(.snappy, value: browser.toast)
        .animation(.snappy(duration: 0.2), value: browser.isFindBarVisible)
        .onAppear(perform: installShortcutMonitor)
        .sheet(isPresented: Bindable(browser).isClearBrowsingDataPresented) {
            ClearBrowsingDataView()
                .environment(browser)
        }
        .sheet(isPresented: Bindable(browser).isOnboardingPresented, onDismiss: browser.finishOnboarding) {
            OnboardingView()
                .environment(browser)
        }
        .sheet(isPresented: Bindable(browser).isChromeImportPresented) {
            ChromeImportView(finishTitle: "Done") { browser.isChromeImportPresented = false }
                .padding(24)
                .frame(width: 460, height: 320)
                .environment(browser)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            browser.saveSession()
        }
    }

    /// Panes are keyed by tab, so a tab keeps its web view's container when a split forms or
    /// separates. Moving the web view between containers lets the outgoing one, still on screen
    /// during its transition, take it back and leave the page blank.
    private var content: some View {
        let tabs = browser.visibleTabs
        let split = browser.activeSplit
        return GeometryReader { proxy in
            let available = max(proxy.size.width - Theme.contentInset, 1)
            HStack(spacing: Theme.contentInset) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    let isLeadingPane = index == 0 && tabs.count == 2
                    card {
                        if tabs.count == 2 {
                            SplitPaneBar(tab: tab, isFocused: tab.id == browser.activeTabID && browser.peek == nil)
                        }
                        if index == 0 { banner }
                        page(for: tab)
                    }
                    .frame(width: isLeadingPane ? available * (split?.ratio ?? 0.5) : nil)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .overlay(alignment: .trailing) {
                        if isLeadingPane {
                            SplitDivider(available: available)
                                .offset(x: Theme.contentInset)
                        }
                    }
                }
                if tabs.isEmpty {
                    card {
                        banner
                        EmptyStateView()
                    }
                }
            }
        }
        .overlay {
            SplitDropPreview()
                .environment(dragController)
        }
        // Closing or separating a pane lets the other grow into its place; switching tabs stays instant.
        .animation(
            tabs.contains { lastSplitTabIDs.contains($0.id) } ? .snappy(duration: 0.28) : nil,
            value: tabs.map(\.id)
        )
        .onChange(of: split.map { [$0.leading, $0.trailing] }, initial: true) { _, ids in
            lastSplitTabIDs = Set(ids ?? [])
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { dragController.contentFrame = $0 }
        .padding(.vertical, Theme.contentInset)
        .padding(.trailing, Theme.contentInset)
    }

    @ViewBuilder private var banner: some View {
        if !browser.isPrivate {
            DefaultBrowserBanner()
        }
    }

    private func card(@ViewBuilder _ page: () -> some View) -> some View {
        VStack(spacing: 0, content: page)
            .clipShape(RoundedRectangle(cornerRadius: Theme.contentCornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: Theme.contentCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            )
    }

    /// Prompts and the find bar belong to the focused pane.
    @ViewBuilder private func page(for tab: Tab) -> some View {
        let isFocused = tab.id == browser.activeTabID && browser.peek == nil
        if tab.internalPage == .history {
            HistoryPage(tab: tab)
                .id(tab.id)
                .simultaneousGesture(focusOnClick(tab))
        } else if tab.internalPage == .downloads {
            DownloadsPage()
                .simultaneousGesture(focusOnClick(tab))
        } else if tab.internalPage == .whatsNew {
            WhatsNewPage()
                .simultaneousGesture(focusOnClick(tab))
        } else {
            webPage(for: tab, isFocused: isFocused, roundsTopCorners: browser.activeSplit == nil)
        }
    }

    /// Web views focus their pane themselves when clicked; Pulse's own pages need this.
    private func focusOnClick(_ tab: Tab) -> some Gesture {
        TapGesture().onEnded { browser.focusPane(of: tab) }
    }

    private func webPage(for tab: Tab, isFocused: Bool, roundsTopCorners: Bool = true) -> some View {
        WebView(tab: tab, takesFocus: isFocused, roundsTopCorners: roundsTopCorners)
            .overlay {
                if let error = tab.loadError {
                    LoadErrorView(tab: tab, error: error)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isFocused, browser.isFindBarVisible {
                    FindBar()
                        .padding(12)
                        .transition(.slide(from: .top, reduceMotion: reduceMotion))
                }
            }
            .overlay(alignment: .topLeading) {
                if isFocused, let request = browser.activePermissionRequest {
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
    }

    /// A link previewed in a card over the dimmed page, like Arc's Peek. Clicking beside it or
    /// pressing Esc closes it, shrinking it away. Expanding skips that: it moves the web view into
    /// a pane, which a still-visible card would take back.
    private func peekOverlay(_ tab: Tab) -> some View {
        ZStack {
            Color.black.opacity(0.22)
                .clipShape(RoundedRectangle(cornerRadius: Theme.contentCornerRadius, style: .continuous))
                .onTapGesture(perform: browser.closePeek)
            card { webPage(for: tab, isFocused: true) }
                .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
                .overlay(alignment: .topTrailing) {
                    PeekControls(expand: expandPeek)
                        .offset(x: PeekControls.width + 10)
                }
                .padding(.horizontal, PeekControls.width + 26)
                .padding(.vertical, 24)
        }
        .padding(.vertical, Theme.contentInset)
        .padding(.trailing, Theme.contentInset)
        .transition(isExpandingPeek ? .asymmetric(insertion: peekTransition, removal: .identity) : peekTransition)
    }

    private var peekTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity)
    }

    /// A view leaves with the transition it had in the update before its removal, hence the extra turn.
    private func expandPeek(intoSplitView: Bool) {
        isExpandingPeek = true
        DispatchQueue.main.async {
            browser.expandPeek(intoSplitView: intoSplitView)
            isExpandingPeek = false
        }
    }

    /// Hovering the collapsed rail slides the full sidebar in over the page, like Arc.
    private var sidebarPeek: some View {
        SidebarView()
            .environment(dragController)
            .environment(swipeTracker)
            .frame(width: sidebarWidth)
            .background(SpaceBackground().environment(swipeTracker))
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
    /// ⌘W may not either: SwiftUI gives it to the system "Close" item or to "Close Tab"
    /// depending on the build, and "Close" closes the window.
    private func installShortcutMonitor() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Every browser window installs a monitor; only the one the key press went to acts.
            guard event.window === browser.window else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 48, modifiers.subtracting(.shift) == .control {
                browser.selectAdjacentTab(offset: modifiers.contains(.shift) ? -1 : 1)
                return nil
            }
            if modifiers == .control, let number = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(number) {
                browser.selectSpace(number: number)
                return nil
            }
            // Esc closes Peek, unless the command bar or find bar is open and takes it.
            if event.keyCode == 53, modifiers.isEmpty, browser.peek != nil,
               browser.commandBar == nil, !browser.isFindBarVisible {
                browser.closePeek()
                return nil
            }
            if modifiers == .command, event.charactersIgnoringModifiers == "w" {
                browser.closeActiveTab()
                return nil
            }
            return event
        }
    }

    /// `WebView` only takes focus when a page is first shown, so closing the bar over the same page
    /// (Esc, or a URL loaded in place) would otherwise leave keys going nowhere until a click.
    /// Waits a runloop so a tab the bar just opened is in the window first.
    private func focusPageAfterCommandBar() {
        DispatchQueue.main.async {
            guard browser.commandBar == nil, let window = browser.window,
                  let webView = browser.focusedTab?.loadedWebView, webView.window === window
            else { return }
            window.makeFirstResponder(webView)
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
    let toast: Toast
    let theme: SpaceTheme
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if let url = toast.sharedURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .background(Theme.activeTabFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(.primary.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .help("Share")
            }
        }
        .foregroundStyle(Theme.sidebarText)
        .padding(.leading, 14)
        .padding(.trailing, toast.sharedURL == nil ? 14 : 6)
        .padding(.vertical, 6)
        .frame(minHeight: 38)
        .background(Theme.sidebarGradient(theme), in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.35)))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .onHover(perform: onHover)
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 16)
        .padding(.trailing, 16)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }
}

/// Beside the Peek card, like Arc's: close it, or keep the page as a tab or in a split view.
private struct PeekControls: View {
    static let width: CGFloat = 30
    @Environment(Browser.self) private var browser
    /// Keeps the page as a tab, in a split view when `true`.
    let expand: (Bool) -> Void

    var body: some View {
        VStack(spacing: 8) {
            button("Close", systemImage: "xmark", help: "Close (Esc)") { browser.closePeek() }
            button("Open as Tab", systemImage: "arrow.up.left.and.arrow.down.right", help: "Open as Tab") {
                expand(false)
            }
            if browser.canExpandPeekIntoSplitView {
                button("Open in Split View", systemImage: "rectangle.split.2x1", help: "Open in Split View") {
                    expand(true)
                }
            }
        }
    }

    private func button(
        _ label: String,
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: Self.width, height: Self.width)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
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
private struct WindowChrome: NSViewRepresentable {
    let browser: Browser
    let showsTrafficLights: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // The view is attached to its window only after this pass.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            browser.window = window
            // A private window can't come back after relaunch: its browser is gone.
            window.isRestorable = !browser.isPrivate
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = !showsTrafficLights
            }
        }
    }
}

/// The tab being dragged from the sidebar, following the pointer anywhere in the window. Over the
/// page it sinks into the split view preview that shows where it will open.
private struct DragGhostLayer: View {
    @Environment(Browser.self) private var browser
    @Environment(SidebarDragController.self) private var dragController
    @State private var origin: CGPoint = .zero

    var body: some View {
        Color.clear
            .overlay(alignment: .topLeading) { ghost }
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
            .allowsHitTesting(false)
    }

    @ViewBuilder private var ghost: some View {
        if let tabID = dragController.draggedTabID,
           let tab = browser.allTabs.first(where: { $0.id == tabID }),
           let size = dragController.tabFrames[tabID]?.size {
            let isOverSplitTarget = dragController.splitDropSide != nil
            SidebarDragGhost(tab: tab, isTile: browser.position(of: tab)?.section == .favorites, size: size)
                .scaleEffect(isOverSplitTarget ? 0.7 : 1)
                .opacity(isOverSplitTarget ? 0 : 1)
                .offset(
                    x: dragController.location.x - dragController.grabOffset.width - size.width / 2 - origin.x,
                    y: dragController.location.y - dragController.grabOffset.height - size.height / 2 - origin.y
                )
        }
    }
}

/// Where a tab dragged onto the page will open: a card in the space's colors over that half,
/// sliding across as the pointer crosses the middle.
private struct SplitDropPreview: View {
    @Environment(Browser.self) private var browser
    @Environment(SidebarDragController.self) private var dragController

    var body: some View {
        ZStack {
            if let side = dragController.splitDropSide,
               let tab = browser.allTabs.first(where: { $0.id == dragController.draggedTabID }) {
                GeometryReader { proxy in
                    ZStack(alignment: side == .leading ? .leading : .trailing) {
                        Color.black.opacity(0.15)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.contentCornerRadius, style: .continuous))
                        SplitDropCard(tab: tab, theme: browser.activeSpace.theme)
                            .frame(width: (proxy.size.width - Theme.contentInset) / 2)
                    }
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SplitDropCard: View {
    let tab: Tab
    let theme: SpaceTheme
    @State private var isSettled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.contentCornerRadius, style: .continuous)
        VStack(spacing: 10) {
            FaviconView(tab: tab, size: 32)
            Text(tab.displayTitle)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 24)
            Text("Open in Split View")
                .font(.system(size: 12))
                .opacity(0.7)
        }
        .foregroundStyle(Theme.sidebarText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarGradient(theme), in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        // Pops in with a little bounce, like a pane making room.
        .scaleEffect(isSettled || reduceMotion ? 1 : 0.9)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) { isSettled = true }
        }
    }
}

/// The gap between split view panes; dragging it resizes them.
private struct SplitDivider: View {
    @Environment(Browser.self) private var browser
    /// The width both panes share.
    let available: Double
    @State private var ratioAtDragStart: Double?

    var body: some View {
        Color.clear
            .frame(width: Theme.contentInset)
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let start = ratioAtDragStart ?? browser.activeSplit?.ratio ?? 0.5
                        ratioAtDragStart = start
                        browser.setSplitRatio(start + value.translation.width / available)
                    }
                    .onEnded { _ in ratioAtDragStart = nil }
            )
            .accessibilityHidden(true)
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

/// The active space's colors behind the window. Every space has a layer, faded in by how far
/// the space position has reached it, so a swipe blends the colors as the fingers move and
/// settling continues that blend instead of starting a new one; gradients don't interpolate.
private struct SpaceBackground: View {
    @Environment(Browser.self) private var browser
    @Environment(SpaceSwipeTracker.self) private var swipeTracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let index = browser.activeSpaceIndex
        let position = reduceMotion ? CGFloat(index) : swipeTracker.position(from: index, spaceCount: browser.spaces.count)
        ZStack {
            ForEach(Array(browser.spaces.enumerated()), id: \.element.id) { offset, space in
                Theme.sidebarGradient(space.theme)
                    .id(space.theme)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: space.theme)
                    // The first layer stays opaque so a blend never shows the window through it.
                    .opacity(offset == 0 ? 1 : min(max(position - CGFloat(offset - 1), 0), 1))
            }
            if let draft = browser.spaceDraft {
                Theme.sidebarGradient(draft.theme)
                    .id(draft.theme)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: browser.spaceDraft?.theme)
        // Matches the sidebar's slide, so the color lands with the space; a fade still suits reduced motion.
        .animation(reduceMotion ? .easeInOut(duration: 0.35) : .snappy(duration: 0.3), value: browser.activeSpaceID)
    }
}
