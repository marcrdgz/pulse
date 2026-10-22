import AppKit
import Observation
import OSLog
import WebKit

enum CommandBarMode: Hashable {
    case newTab
    case editActiveTab
}

@Observable
final class Browser {
    private(set) var pinnedTabs: [Tab] = []
    /// Newest first, like Arc's "Today" section.
    private(set) var todayTabs: [Tab] = []
    private(set) var activeTabID: Tab.ID?
    private(set) var commandBar: CommandBarMode?
    private(set) var toast: String?
    var isSidebarVisible = true
    private(set) var isFindBarVisible = false
    /// Bumped on every ⌘F so the find bar refocuses its field even when already open.
    private(set) var findBarActivation = 0
    var findQuery = ""
    private(set) var isFindQueryMissing = false
    private var closedTabs: [ClosedTab] = []

    @ObservationIgnored let downloads = DownloadManager()
    @ObservationIgnored private let sessionStore: SessionStore?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    private struct ClosedTab {
        let url: URL
        let title: String
        let index: Int
    }

    init(sessionStore: SessionStore? = nil) {
        self.sessionStore = sessionStore
        downloads.browser = self
        if let session = sessionStore?.load() {
            restore(session)
        }
        if activeTab == nil {
            commandBar = .newTab
        }
    }

    /// Pinned tabs first, then today tabs: the order ⌘1…⌘9 and tab cycling follow.
    var allTabs: [Tab] { pinnedTabs + todayTabs }

    var activeTab: Tab? {
        allTabs.first { $0.id == activeTabID }
    }

    var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    // MARK: Tabs

    @discardableResult
    func openTab(url: URL, activate: Bool = true) -> Tab {
        let tab = makeTab(url: url)
        todayTabs.insert(tab, at: 0)
        if activate {
            select(tab)
        } else {
            scheduleSave()
        }
        return tab
    }

    /// Creates the tab WebKit needs for `window.open` / `target=_blank` and returns its web view.
    func openPopup(configuration: WKWebViewConfiguration) -> WKWebView {
        let tab = openTab(url: URL(string: "about:blank")!)
        return tab.adoptWebView(configuration: configuration)
    }

    func select(_ tab: Tab?) {
        if tab?.id != activeTabID { isFindBarVisible = false }
        activeTabID = tab?.id
        scheduleSave()
    }

    func selectTab(number: Int) {
        let tabs = allTabs
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        select(tabs[index])
    }

    func selectAdjacentTab(offset: Int) {
        let tabs = allTabs
        guard !tabs.isEmpty else { return }
        guard let current = tabs.firstIndex(where: { $0.id == activeTabID }) else {
            select(tabs.first)
            return
        }
        select(tabs[(current + offset % tabs.count + tabs.count) % tabs.count])
    }

    /// Pinned tabs are never removed: closing one resets it to its pinned page, like Arc.
    func close(_ tab: Tab) {
        let wasActive = tab.id == activeTabID

        if tab.isPinned {
            tab.resetToPinnedURL()
            if wasActive { select(todayTabs.first) }
        } else if let index = todayTabs.firstIndex(where: { $0.id == tab.id }) {
            todayTabs.remove(at: index)
            tab.unload()
            closedTabs.append(ClosedTab(url: tab.url, title: tab.title, index: index))
            if wasActive {
                select(todayTabs.indices.contains(index) ? todayTabs[index] : todayTabs.last)
            }
        }

        if activeTab == nil {
            commandBar = .newTab
        }
        scheduleSave()
    }

    func closeActiveTab() {
        if let activeTab { close(activeTab) }
    }

    func reopenClosedTab() {
        guard let closed = closedTabs.popLast() else { return }
        let tab = makeTab(url: closed.url, title: closed.title)
        todayTabs.insert(tab, at: min(closed.index, todayTabs.count))
        commandBar = nil
        select(tab)
    }

    func togglePin(_ tab: Tab) {
        if let index = pinnedTabs.firstIndex(where: { $0.id == tab.id }) {
            pinnedTabs.remove(at: index)
            tab.pinnedURL = nil
            todayTabs.insert(tab, at: 0)
        } else if let index = todayTabs.firstIndex(where: { $0.id == tab.id }) {
            todayTabs.remove(at: index)
            tab.pinnedURL = tab.url
            pinnedTabs.append(tab)
        }
        scheduleSave()
    }

    func copyURL(of tab: Tab) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tab.url.absoluteString, forType: .string)
        showToast("Copied URL")
    }

    // MARK: Command bar

    func showCommandBar(_ mode: CommandBarMode) {
        commandBar = mode == .editActiveTab && activeTab == nil ? .newTab : mode
    }

    func dismissCommandBar() {
        commandBar = nil
    }

    func open(_ url: URL, from mode: CommandBarMode) {
        commandBar = nil
        if mode == .editActiveTab, let activeTab {
            activeTab.load(url)
        } else {
            openTab(url: url)
        }
    }

    func switchTo(_ tab: Tab) {
        commandBar = nil
        select(tab)
    }

    // MARK: Find

    func showFindBar() {
        guard activeTab != nil else { return }
        isFindBarVisible = true
        findBarActivation += 1
    }

    func hideFindBar() {
        isFindBarVisible = false
        isFindQueryMissing = false
        activeTab?.clearFindSelection()
    }

    func findInPage(backwards: Bool = false) {
        guard let tab = activeTab, !findQuery.isEmpty else {
            isFindQueryMissing = false
            return
        }
        let query = findQuery
        Task {
            let found = await tab.find(query, backwards: backwards)
            if query == findQuery { isFindQueryMissing = !found }
        }
    }

    // MARK: Chrome

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Session

    var session: Session {
        Session(
            pinnedTabs: pinnedTabs.map(Session.SavedTab.init),
            todayTabs: todayTabs.map(Session.SavedTab.init),
            activeTabID: activeTabID
        )
    }

    func tabDidUpdate() {
        scheduleSave()
    }

    func saveSession() {
        saveTask?.cancel()
        guard let sessionStore else { return }
        do {
            try sessionStore.save(session)
        } catch {
            Logger.session.error("Failed to save session: \(error.localizedDescription)")
        }
    }

    private func scheduleSave() {
        guard sessionStore != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveSession()
        }
    }

    private func restore(_ session: Session) {
        pinnedTabs = session.pinnedTabs.map(makeTab)
        todayTabs = session.todayTabs.map(makeTab)
        activeTabID = allTabs.contains { $0.id == session.activeTabID }
            ? session.activeTabID
            : (todayTabs.first ?? pinnedTabs.first)?.id
    }

    private func makeTab(_ saved: Session.SavedTab) -> Tab {
        let tab = Tab(id: saved.id, url: saved.url, title: saved.title, pinnedURL: saved.pinnedURL)
        tab.browser = self
        tab.loadFavicon()
        return tab
    }

    private func makeTab(url: URL, title: String = "") -> Tab {
        let tab = Tab(url: url, title: title)
        tab.browser = self
        return tab
    }
}

private extension Session.SavedTab {
    init(_ tab: Tab) {
        self.init(id: tab.id, url: tab.url, title: tab.title, pinnedURL: tab.pinnedURL)
    }
}

private extension Logger {
    static let session = Logger(subsystem: "dev.doblefilo.pulse", category: "Session")
}
