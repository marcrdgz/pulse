import SwiftUI

struct SidebarView: View {
    @Environment(Browser.self) private var browser
    @State private var dragController = SidebarDragController()
    @State private var frame: CGRect = .zero
    @State private var middleClickMonitor: Any?
    @Namespace private var activeHighlight

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarToolbar()
            SidebarAddressBar()
            if !browser.pinnedTabs.isEmpty || dragController.isDragging {
                PinnedTabsGrid()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Rectangle()
                .fill(Theme.sidebarText.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 4)
            NewTabButton()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(browser.todayTabs) { tab in
                        TabRow(tab: tab, highlightNamespace: activeHighlight)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: dragController.isDragging ? 44 : 0, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                        .fill(dragController.pendingSection == .today ? Theme.hoverFill : .clear)
                )
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    dragController.todayAreaFrame = frame
                }
                .animation(.snappy(duration: 0.22), value: browser.todayTabs.map(\.id))
                .animation(.snappy(duration: 0.2), value: browser.activeTabID)
            }
            .scrollIndicators(.never)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                dragController.todayViewportFrame = frame
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .foregroundStyle(Theme.sidebarText)
        .overlay(alignment: .topLeading) { dragGhost }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .environment(dragController)
        .animation(.snappy(duration: 0.22), value: browser.pinnedTabs.isEmpty)
        .animation(.snappy(duration: 0.22), value: dragController.isDragging)
        .onAppear(perform: installMiddleClickMonitor)
        .onDisappear(perform: removeMiddleClickMonitor)
    }

    @ViewBuilder private var dragGhost: some View {
        if let tabID = dragController.draggedTabID,
           let tab = browser.allTabs.first(where: { $0.id == tabID }),
           let size = dragController.tabFrames[tabID]?.size {
            SidebarDragGhost(tab: tab, size: size)
                .offset(
                    x: dragController.location.x - dragController.grabOffset.width - size.width / 2 - frame.minX,
                    y: dragController.location.y - dragController.grabOffset.height - size.height / 2 - frame.minY
                )
        }
    }

    /// Middle-click closes the tab under the pointer; SwiftUI has no gesture for other mouse buttons.
    private func installMiddleClickMonitor() {
        guard middleClickMonitor == nil else { return }
        middleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            guard event.buttonNumber == 2, let contentView = event.window?.contentView else { return event }
            let point = CGPoint(x: event.locationInWindow.x, y: contentView.bounds.height - event.locationInWindow.y)
            guard let tab = dragController.tab(at: point, in: browser) else { return event }
            browser.close(tab)
            return nil
        }
    }

    private func removeMiddleClickMonitor() {
        if let middleClickMonitor { NSEvent.removeMonitor(middleClickMonitor) }
        middleClickMonitor = nil
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
