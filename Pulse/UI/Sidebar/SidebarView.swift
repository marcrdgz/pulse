import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(Browser.self) private var browser
    @State private var dragController = SidebarDragController()
    @State private var swipeTracker = SpaceSwipeTracker()
    @State private var frame: CGRect = .zero
    @State private var eventMonitors: [Any] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarToolbar()
            SidebarAddressBar()
            if !browser.favorites.isEmpty || dragController.showsDropZones {
                FavoritesGrid()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            spacePager
            SpaceSwitcher()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .foregroundStyle(Theme.sidebarText)
        .overlay(alignment: .topLeading) { dragGhost }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .environment(dragController)
        .animation(.snappy(duration: 0.22), value: browser.favorites.isEmpty)
        .animation(.snappy(duration: 0.22), value: dragController.isDragging)
        .onAppear(perform: installEventMonitors)
        .onDisappear(perform: removeEventMonitors)
    }

    /// All spaces side by side, offset to the active one, so switching slides like Arc.
    private var spacePager: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                ForEach(browser.spaces) { space in
                    let isActive = space.id == browser.activeSpaceID
                    SpaceContent(space: space, isActive: isActive)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .allowsHitTesting(isActive)
                }
            }
            .frame(width: proxy.size.width * CGFloat(browser.spaces.count), alignment: .leading)
            .offset(x: -proxy.size.width * CGFloat(browser.activeSpaceIndex))
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: browser.activeSpaceID)
        }
        .clipped()
    }

    @ViewBuilder private var dragGhost: some View {
        if let tabID = dragController.draggedTabID,
           let tab = browser.allTabs.first(where: { $0.id == tabID }),
           let size = dragController.tabFrames[tabID]?.size {
            SidebarDragGhost(tab: tab, isTile: browser.position(of: tab)?.section == .favorites, size: size)
                .offset(
                    x: dragController.location.x - dragController.grabOffset.width - size.width / 2 - frame.minX,
                    y: dragController.location.y - dragController.grabOffset.height - size.height / 2 - frame.minY
                )
        }
    }

    /// Events SwiftUI has no gestures for: middle-click closes the tab under the pointer,
    /// and a horizontal two-finger swipe over the sidebar switches spaces.
    private func installEventMonitors() {
        guard eventMonitors.isEmpty else { return }
        let middleClick = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            guard event.buttonNumber == 2, let point = windowPoint(of: event),
                  let tab = dragController.tab(at: point, in: browser)
            else { return event }
            browser.close(tab)
            return nil
        }
        let swipe = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let point = windowPoint(of: event), frame.contains(point) else { return event }
            if let offset = swipeTracker.offset(for: event) {
                browser.selectAdjacentSpace(offset: offset)
            }
            return swipeTracker.isConsumingGesture ? nil : event
        }
        eventMonitors = [middleClick, swipe].compactMap { $0 }
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
    }

    /// The event's location in the same top-left window coordinates as SwiftUI's `.global`;
    /// `nil` for events in other windows, which have sidebars of their own.
    private func windowPoint(of event: NSEvent) -> CGPoint? {
        guard event.window === browser.window, let contentView = event.window?.contentView else { return nil }
        return CGPoint(x: event.locationInWindow.x, y: contentView.bounds.height - event.locationInWindow.y)
    }
}

/// The row the traffic lights live in, with Arc's navigation buttons on the right.
private struct SidebarToolbar: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        let tab = browser.activeTab
        HStack(spacing: 2) {
            Spacer()
            if let extensions = browser.extensions {
                ExtensionsButton(extensions: extensions)
            }
            Button(action: browser.toggleSidebar) {
                Image(systemName: "sidebar.left")
            }
            .accessibilityLabel("Toggle Sidebar")
            .help("Toggle Sidebar (⌘S)")
            Button { tab?.goBack() } label: {
                Image(systemName: "arrow.left")
            }
            .accessibilityLabel("Back")
            .disabled(!(tab?.canGoBack ?? false))
            .help("Back (⌘[)")
            Button { tab?.goForward() } label: {
                Image(systemName: "arrow.right")
            }
            .accessibilityLabel("Forward")
            .disabled(!(tab?.canGoForward ?? false))
            .help("Forward (⌘])")
            Button {
                if tab?.isLoading == true { tab?.stopLoading() } else { tab?.reload() }
            } label: {
                Image(systemName: tab?.isLoading == true ? "xmark" : "arrow.clockwise")
            }
            .accessibilityLabel(tab?.isLoading == true ? "Stop" : "Reload")
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
