import AppKit
import Observation
import OSLog
import WebKit

enum TabSection: Hashable {
    case favorites
    case pinned
    case today
}

/// A slot in the favorites or in one of the active space's sections.
struct TabPosition: Hashable {
    var section: TabSection
    var index: Int
}

enum CommandBarMode: Hashable {
    case newTab
    case editActiveTab
}

@Observable
final class Browser {
    /// Shared by every space, shown as the favicon grid.
    private(set) var favorites: [Tab] = []
    /// Never empty.
    private(set) var spaces: [Space]
    private(set) var activeSpaceID: Space.ID
    private(set) var commandBar: CommandBarMode?
    private(set) var toast: String?
    var isSidebarExpanded = true
    private(set) var isFindBarVisible = false
    /// Bumped on every ⌘F so the find bar refocuses its field even when already open.
    private(set) var findBarActivation = 0
    var findQuery = ""
    private(set) var isFindQueryMissing = false
    /// The space whose name is being edited in the sidebar.
    private(set) var renamingSpaceID: Space.ID?
    var isClearBrowsingDataPresented = false
    /// Chrome's download bubble, anchored to the sidebar's downloads button.
    var isDownloadsBubblePresented = false
    /// Sites waiting for a camera/microphone answer, oldest first.
    private(set) var permissionRequests: [PermissionRequest] = []
    private var closedTabs: [ClosedTab] = []

    @ObservationIgnored let downloads: DownloadManager
    @ObservationIgnored let preferences: Preferences
    @ObservationIgnored let history: HistoryStore?
    @ObservationIgnored private let sessionStore: SessionStore?
    @ObservationIgnored let sitePermissions: SitePermissionStore?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    struct ClosedTab: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
        let spaceID: Space.ID
        let index: Int
    }

    init(
        sessionStore: SessionStore? = nil,
        history: HistoryStore? = nil,
        sitePermissions: SitePermissionStore? = nil,
        downloads: DownloadManager = DownloadManager(),
        preferences: Preferences = Preferences()
    ) {
        let home = Space(name: "Home", theme: .purple)
        spaces = [home]
        activeSpaceID = home.id
        self.sessionStore = sessionStore
        self.history = history
        self.sitePermissions = sitePermissions
        self.downloads = downloads
        self.preferences = preferences
        downloads.browser = self
        if let session = sessionStore?.load() {
            restore(session)
            if preferences.startupBehavior == .clearToday { clearToday() }
        }
        if activeTab == nil {
            commandBar = .newTab
        }
    }

    var activeSpace: Space {
        spaces.first { $0.id == activeSpaceID } ?? spaces[0]
    }

    var pinnedTabs: [Tab] { activeSpace.pinnedTabs }
    var todayTabs: [Tab] { activeSpace.todayTabs }

    /// Favorites, then the active space's pinned and today tabs: the order ⌘1…⌘9 and tab cycling follow.
    var allTabs: [Tab] { favorites + activeSpace.tabs }

    /// Every open tab, the active space's first; what the command bar searches.
    var everyTab: [Tab] {
        allTabs + spaces.filter { $0.id != activeSpaceID }.flatMap(\.tabs)
    }

    var activeTabID: Tab.ID? { activeSpace.activeTabID }

    var activeTab: Tab? {
        allTabs.first { $0.id == activeTabID }
    }

    var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    /// Most recently closed first, for the History menu.
    var recentlyClosedTabs: [ClosedTab] { Array(closedTabs.reversed().prefix(10)) }

    func space(containing tab: Tab) -> Space? {
        spaces.first { $0.contains(tab) }
    }

    // MARK: Tabs

    @discardableResult
    func openTab(url: URL, activate: Bool = true) -> Tab {
        let tab = makeTab(url: url)
        activeSpace.todayTabs.insert(tab, at: 0)
        if activate {
            select(tab)
        } else {
            scheduleSave()
        }
        return tab
    }

    /// Links opened from other apps: a new foreground tab in the current space, like Chrome.
    func openExternalURL(_ url: URL) {
        commandBar = nil
        openTab(url: url)
    }

    /// Creates the tab WebKit needs for `window.open` / `target=_blank` and returns its web view.
    func openPopup(from opener: Tab, configuration: WKWebViewConfiguration) -> WKWebView {
        let tab = openTab(url: URL(string: "about:blank")!)
        tab.opener = opener
        return tab.adoptWebView(configuration: configuration)
    }

    /// Selecting a tab from another space switches to that space.
    func select(_ tab: Tab?) {
        if let tab, let owner = space(containing: tab), owner.id != activeSpaceID {
            activeSpaceID = owner.id
        }
        if tab?.id != activeTabID { isFindBarVisible = false }
        activeSpace.activeTabID = tab?.id
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

    /// Favorites and pinned tabs are never removed: closing one resets it to its pinned page, like Arc.
    func close(_ tab: Tab) {
        denyPermissionRequests(from: tab)
        if tab.isPinned {
            tab.resetToPinnedURL()
            if tab.id == activeTabID { select(todayTabs.first) }
        } else if let space = space(containing: tab),
                  let index = space.todayTabs.firstIndex(where: { $0.id == tab.id }) {
            space.todayTabs.remove(at: index)
            tab.unload()
            if tab.url.absoluteString != "about:blank" {
                closedTabs.append(ClosedTab(url: tab.url, title: tab.title, spaceID: space.id, index: index))
            }
            if space.activeTabID == tab.id {
                if space.id == activeSpaceID { isFindBarVisible = false }
                // Like Chrome, closing a popup or a link opened in a new tab returns to the page that opened it.
                let opener = tab.opener.flatMap { opener in (favorites + space.tabs).first { $0 === opener } }
                let neighbor = space.todayTabs.indices.contains(index) ? space.todayTabs[index] : space.todayTabs.last
                space.activeTabID = (opener ?? neighbor)?.id
            }
        }

        if activeTab == nil {
            commandBar = .newTab
        }
        scheduleSave()
    }

    // MARK: History

    /// On commit the tab still has the previous page's title; the new one arrives through
    /// `tabTitleDidChange`, so an empty title keeps whatever the URL had.
    func recordVisit(to tab: Tab, title: String = "") {
        guard tab.url.isWebPage else { return }
        history?.recordVisit(url: tab.url, title: title)
    }

    func tabTitleDidChange(_ tab: Tab) {
        guard tab.url.isWebPage else { return }
        history?.updateTitle(tab.title, for: tab.url)
    }

    // MARK: Downloads

    /// ⌘⇧J opens the downloads page in a new tab, like Chrome.
    func showDownloads() {
        commandBar = nil
        isDownloadsBubblePresented = false
        openTab(url: InternalPage.downloads.url)
    }

    /// Chrome opens its download bubble when a download starts; with the sidebar collapsed there's
    /// nothing to anchor it to, so a toast says it instead.
    func downloadDidStart(_ download: Download) {
        if isSidebarExpanded {
            isDownloadsBubblePresented = true
        } else {
            showToast("Downloading \(download.filename)…")
        }
    }

    func downloadDidFinish(_ download: Download) {
        guard !isDownloadsBubblePresented else { return }
        switch download.state {
        case .completed: showToast("Downloaded \(download.filename)")
        case .failed: showToast("Couldn't download \(download.filename)")
        default: break
        }
    }

    // MARK: History

    /// ⌘Y opens the history page in a new tab, like Chrome.
    func showHistory() {
        commandBar = nil
        openTab(url: InternalPage.history.url)
    }

    func showClearBrowsingData() {
        commandBar = nil
        isClearBrowsingDataPresented = true
    }

    /// Opens a page in the current tab, or a new one when there's none.
    func navigate(to url: URL) {
        commandBar = nil
        if let activeTab {
            activeTab.load(url)
        } else {
            openTab(url: url)
        }
    }

    // MARK: Permissions

    /// The prompt to show: the oldest request from the visible tab.
    var activePermissionRequest: PermissionRequest? {
        permissionRequests.first { $0.tabID == activeTabID }
    }

    /// Answers at once when the user already decided for this site, otherwise queues a prompt.
    func requestPermission(
        from tab: Tab,
        origin: String,
        kinds: [PermissionKind],
        respond: @escaping (WKPermissionDecision) -> Void
    ) {
        if let isAllowed = sitePermissions?.decision(for: origin, kinds: kinds) {
            respond(isAllowed ? .grant : .deny)
            return
        }
        permissionRequests.append(PermissionRequest(tabID: tab.id, origin: origin, kinds: kinds, respond: respond))
    }

    func answer(_ request: PermissionRequest, with choice: PermissionChoice) {
        guard let index = permissionRequests.firstIndex(where: { $0.id == request.id }) else { return }
        permissionRequests.remove(at: index)
        switch choice {
        case .allowAlways:
            sitePermissions?.save(true, for: request.origin, kinds: request.kinds)
            request.respond(.grant)
        case .allowOnce:
            request.respond(.grant)
        case .neverAllow:
            sitePermissions?.save(false, for: request.origin, kinds: request.kinds)
            request.respond(.deny)
        }
    }

    private func denyPermissionRequests(from tab: Tab) {
        let pending = permissionRequests.filter { $0.tabID == tab.id }
        permissionRequests.removeAll { $0.tabID == tab.id }
        pending.forEach { $0.respond(.deny) }
    }

    func closeActiveTab() {
        if let activeTab { close(activeTab) }
    }

    /// Reopens into the space the tab was closed from, if it still exists.
    func reopenClosedTab() {
        if let closed = closedTabs.last { reopen(closed) }
    }

    func reopen(_ closed: ClosedTab) {
        closedTabs.removeAll { $0.id == closed.id }
        let space = spaces.first { $0.id == closed.spaceID } ?? activeSpace
        let tab = makeTab(url: closed.url, title: closed.title)
        space.todayTabs.insert(tab, at: min(closed.index, space.todayTabs.count))
        commandBar = nil
        select(tab)
    }

    /// Pins to, or unpins from, the active space's pinned list.
    func togglePin(_ tab: Tab) {
        if position(of: tab)?.section == .pinned {
            moveTab(tab, to: TabPosition(section: .today, index: 0))
        } else {
            moveTab(tab, to: TabPosition(section: .pinned, index: pinnedTabs.count))
        }
    }

    func toggleFavorite(_ tab: Tab) {
        if position(of: tab)?.section == .favorites {
            moveTab(tab, to: TabPosition(section: .today, index: 0))
        } else {
            moveTab(tab, to: TabPosition(section: .favorites, index: favorites.count))
        }
    }

    /// Where the tab sits: in the favorites, or in the space that owns it.
    func position(of tab: Tab) -> TabPosition? {
        if let index = favorites.firstIndex(where: { $0.id == tab.id }) {
            return TabPosition(section: .favorites, index: index)
        }
        guard let space = space(containing: tab) else { return nil }
        if let index = space.pinnedTabs.firstIndex(where: { $0.id == tab.id }) {
            return TabPosition(section: .pinned, index: index)
        }
        return space.todayTabs.firstIndex { $0.id == tab.id }.map { TabPosition(section: .today, index: $0) }
    }

    /// Moves a tab into the favorites or a section of the active space, pinning or unpinning it
    /// as needed. `destination.index` counts the section's tabs without the moved one.
    func moveTab(_ tab: Tab, to destination: TabPosition) {
        guard detach(tab) else { return }
        switch destination.section {
        case .favorites:
            tab.pinnedURL = tab.pinnedURL ?? tab.url
            favorites.insert(tab, at: min(destination.index, favorites.count))
        case .pinned:
            tab.pinnedURL = tab.pinnedURL ?? tab.url
            activeSpace.pinnedTabs.insert(tab, at: min(destination.index, activeSpace.pinnedTabs.count))
        case .today:
            tab.pinnedURL = nil
            activeSpace.todayTabs.insert(tab, at: min(destination.index, activeSpace.todayTabs.count))
        }
        scheduleSave()
    }

    /// Moves a tab to the top of another space's today tabs and follows it there.
    func moveTab(_ tab: Tab, to space: Space) {
        guard detach(tab) else { return }
        tab.pinnedURL = nil
        space.todayTabs.insert(tab, at: 0)
        select(tab)
    }

    /// An empty title restores the page's own title.
    func rename(_ tab: Tab, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        tab.customTitle = trimmed.isEmpty ? nil : trimmed
        scheduleSave()
    }

    private func detach(_ tab: Tab) -> Bool {
        if let index = favorites.firstIndex(where: { $0.id == tab.id }) {
            favorites.remove(at: index)
            return true
        }
        guard let space = space(containing: tab) else { return false }
        space.pinnedTabs.removeAll { $0.id == tab.id }
        space.todayTabs.removeAll { $0.id == tab.id }
        return true
    }

    // MARK: Spaces

    var activeSpaceIndex: Int {
        spaces.firstIndex { $0.id == activeSpaceID } ?? 0
    }

    @discardableResult
    func createSpace() -> Space {
        let theme = SpaceTheme.allCases[spaces.count % SpaceTheme.allCases.count]
        let space = Space(name: "Space \(spaces.count + 1)", theme: theme)
        spaces.append(space)
        selectSpace(space)
        commandBar = .newTab
        return space
    }

    func selectSpace(_ space: Space) {
        guard space.id != activeSpaceID, spaces.contains(where: { $0.id == space.id }) else { return }
        activeSpaceID = space.id
        isFindBarVisible = false
        commandBar = nil
        scheduleSave()
    }

    func selectSpace(number: Int) {
        guard spaces.indices.contains(number - 1) else { return }
        selectSpace(spaces[number - 1])
    }

    /// Doesn't wrap around, like swiping between Arc spaces.
    func selectAdjacentSpace(offset: Int) {
        let index = activeSpaceIndex + offset
        guard spaces.indices.contains(index) else { return }
        selectSpace(spaces[index])
    }

    func rename(_ space: Space, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        space.name = trimmed
        scheduleSave()
    }

    func beginRenaming(_ space: Space) {
        selectSpace(space)
        renamingSpaceID = space.id
    }

    func endRenaming() {
        renamingSpaceID = nil
    }

    func setTheme(_ theme: SpaceTheme, for space: Space) {
        space.theme = theme
        scheduleSave()
    }

    /// Closes the space's pinned and today tabs; favorites stay. The last space can't be deleted.
    func delete(_ space: Space) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        space.tabs.forEach { $0.unload() }
        spaces.remove(at: index)
        if activeSpaceID == space.id {
            activeSpaceID = spaces[min(index, spaces.count - 1)].id
            isFindBarVisible = false
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

    /// `isTyped` marks addresses the user typed, which Chrome ranks first in suggestions.
    func open(_ url: URL, from mode: CommandBarMode, isTyped: Bool = false) {
        if isTyped { history?.recordTyped(url) }
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
        isSidebarExpanded.toggle()
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
            favorites: favorites.map(Session.SavedTab.init),
            spaces: spaces.map { space in
                Session.SavedSpace(
                    id: space.id,
                    name: space.name,
                    theme: space.theme.rawValue,
                    pinnedTabs: space.pinnedTabs.map(Session.SavedTab.init),
                    todayTabs: space.todayTabs.map(Session.SavedTab.init),
                    activeTabID: space.activeTabID
                )
            },
            activeSpaceID: activeSpaceID
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
        favorites = session.favorites.map(makeTab)
        let restoredSpaces = session.spaces.map { saved in
            Space(
                id: saved.id,
                name: saved.name,
                theme: SpaceTheme(rawValue: saved.theme) ?? .purple,
                pinnedTabs: saved.pinnedTabs.map(makeTab),
                todayTabs: saved.todayTabs.map(makeTab),
                activeTabID: saved.activeTabID
            )
        }
        guard let firstSpace = restoredSpaces.first else { return }
        spaces = restoredSpaces
        activeSpaceID = restoredSpaces.first { $0.id == session.activeSpaceID }?.id ?? firstSpace.id

        // A saved active tab that no longer exists falls back to the space's first tab.
        for space in spaces where space.activeTabID != nil {
            let tabs = favorites + space.tabs
            if !tabs.contains(where: { $0.id == space.activeTabID }) {
                space.activeTabID = (space.todayTabs.first ?? space.pinnedTabs.first ?? favorites.first)?.id
            }
        }
    }

    /// "Start with an empty Today": favorites and pinned tabs stay, today tabs are closed.
    private func clearToday() {
        for space in spaces {
            space.todayTabs.removeAll()
            if !(favorites + space.pinnedTabs).contains(where: { $0.id == space.activeTabID }) {
                space.activeTabID = nil
            }
        }
    }

    private func makeTab(_ saved: Session.SavedTab) -> Tab {
        let tab = Tab(id: saved.id, url: saved.url, title: saved.title, pinnedURL: saved.pinnedURL)
        tab.customTitle = saved.customTitle
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
        self.init(id: tab.id, url: tab.url, title: tab.title, customTitle: tab.customTitle, pinnedURL: tab.pinnedURL)
    }
}

extension Logger {
    static let session = Logger(subsystem: "dev.doblefilo.pulse", category: "Session")
}
