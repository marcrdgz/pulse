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

/// A transient notice in the window's top-right corner, like Arc's.
struct Toast: Equatable {
    let message: String
    /// Offered through a share button when set.
    var sharedURL: URL?
}

enum CommandBarMode: Hashable {
    case newTab
    case editActiveTab
    /// Opens the page next to the active tab in a split view.
    case splitView
}

@Observable
final class Browser: NSObject {
    /// The default profile first. Private windows only use the default one.
    private(set) var profiles: [Profile] = [.default]
    /// Shared by every space of a profile, shown as the favicon grid.
    private var favoritesByProfile: [Profile.ID: [Tab]] = [:]
    /// Never empty.
    private(set) var spaces: [Space]
    private(set) var activeSpaceID: Space.ID
    private(set) var commandBar: CommandBarMode?
    private(set) var toast: Toast?
    var isSidebarExpanded = true
    private(set) var isFindBarVisible = false
    /// Bumped on every ⌘F so the find bar refocuses its field even when already open.
    private(set) var findBarActivation = 0
    var findQuery = ""
    private(set) var isFindQueryMissing = false
    /// The space whose name is being edited in the sidebar.
    private(set) var renamingSpaceID: Space.ID?
    /// The space whose icon picker is open in the sidebar.
    private(set) var editingIconSpaceID: Space.ID?
    /// A space being set up in the sidebar's "Create a Space" form; not in `spaces` until committed.
    private(set) var spaceDraft: Space?
    var isClearBrowsingDataPresented = false
    /// Shown on the very first launch, before any session exists.
    var isOnboardingPresented = false
    var isChromeImportPresented = false
    /// Chrome's download bubble, anchored to the sidebar's downloads button.
    var isDownloadsBubblePresented = false
    /// Sites waiting for a camera/microphone answer, oldest first.
    private(set) var permissionRequests: [PermissionRequest] = []
    /// A link previewed over the page, like Arc's Peek; one of the space's tabs only once expanded.
    private(set) var peek: Tab?
    private var closedTabs: [ClosedTab] = []

    /// Private windows keep cookies and storage in memory and record no history or session.
    let isPrivate: Bool
    @ObservationIgnored let downloads: DownloadManager
    @ObservationIgnored let contentBlocker: ContentBlocker
    /// `nil` in private windows, which run no extensions.
    @ObservationIgnored let extensions: WebExtensions?
    /// Private windows keep every page's data in this one in-memory store.
    @ObservationIgnored private let privateDataStore: WKWebsiteDataStore?
    /// One per profile but the default, made when a page first needs it.
    @ObservationIgnored private var profileDataStores: [Profile.ID: WKWebsiteDataStore] = [:]
    /// Without a restored session every profile would look deleted.
    @ObservationIgnored private var didRestoreSession = false
    @ObservationIgnored let faviconLoader: FaviconLoader
    /// The window showing this browser, so event monitors only act on their own window's events.
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored let preferences: Preferences
    @ObservationIgnored let history: HistoryStore?
    @ObservationIgnored private let sessionStore: SessionStore?
    @ObservationIgnored let sitePermissions: SitePermissionStore?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var hibernationTask: Task<Void, Never>?

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
        contentBlocker: ContentBlocker = ContentBlocker(),
        extensions: WebExtensions? = nil,
        preferences: Preferences = Preferences(),
        isPrivate: Bool = false
    ) {
        let home = isPrivate ? Space(name: "Private", theme: .graphite) : Space(name: "Home", theme: .purple)
        spaces = [home]
        activeSpaceID = home.id
        self.sessionStore = sessionStore
        self.history = history
        self.sitePermissions = sitePermissions
        self.downloads = downloads
        self.contentBlocker = contentBlocker
        self.extensions = extensions
        self.preferences = preferences
        self.isPrivate = isPrivate
        privateDataStore = isPrivate ? .nonPersistent() : nil
        faviconLoader = isPrivate ? .ephemeral : .shared
        super.init()
        downloads.browser = self
        contentBlocker.register(self)
        contentBlocker.start()
        if let session = sessionStore?.load() {
            restore(session)
            if preferences.startupBehavior == .clearToday { clearToday() }
        } else if sessionStore != nil, !preferences.hasCompletedOnboarding {
            isOnboardingPresented = true
        }
        if sessionStore != nil {
            announceUpdate(to: Bundle.main.shortVersion, releases: ReleaseNotes.bundled)
        }
        if activeTab == nil, !isOnboardingPresented {
            commandBar = .newTab
        }
        extensions?.register(self)
    }

    /// A private window's browser: nothing it does is written to disk, except downloads.
    static func makePrivate(contentBlocker: ContentBlocker, preferences: Preferences) -> Browser {
        Browser(
            downloads: DownloadManager(preferences: preferences),
            contentBlocker: contentBlocker,
            preferences: preferences,
            isPrivate: true
        )
    }

    var activeSpace: Space {
        spaces.first { $0.id == activeSpaceID } ?? spaces[0]
    }

    /// The active space's profile's favorites.
    private(set) var favorites: [Tab] {
        get { favorites(in: activeSpace.profileID) }
        set { favoritesByProfile[activeSpace.profileID] = newValue }
    }

    func favorites(in profileID: Profile.ID) -> [Tab] {
        favoritesByProfile[profileID] ?? []
    }

    /// Every tab of every profile, in a stable order.
    var tabsInAllProfiles: [Tab] {
        profiles.flatMap { favorites(in: $0.id) } + spaces.flatMap(\.tabs)
    }

    var pinnedTabs: [Tab] { activeSpace.pinnedTabs }
    var todayTabs: [Tab] { activeSpace.todayTabs }

    /// Favorites, then the active space's pinned and today tabs: the order ⌘1…⌘9 and tab cycling follow.
    var allTabs: [Tab] { favorites + activeSpace.tabs }

    /// Every tab reachable from the sidebar of some space, the active space's first; what the
    /// command bar searches. Favorites of profiles other than the active one are left out.
    var everyTab: [Tab] {
        allTabs + spaces.filter { $0.id != activeSpaceID }.flatMap(\.tabs)
    }

    var activeTabID: Tab.ID? { activeSpace.activeTabID }

    var activeTab: Tab? {
        allTabs.first { $0.id == activeTabID }
    }

    /// The page keyboard input and page commands go to: Peek while it's open, the active tab otherwise.
    var focusedTab: Tab? { peek ?? activeTab }

    var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    /// Most recently closed first, for the History menu.
    var recentlyClosedTabs: [ClosedTab] { Array(closedTabs.reversed().prefix(10)) }

    func space(containing tab: Tab) -> Space? {
        spaces.first { $0.contains(tab) }
    }

    // MARK: Tabs

    /// Opens at the top of the space's today tabs; activating a tab in another space switches to it.
    @discardableResult
    func openTab(url: URL, in space: Space? = nil, activate: Bool = true) -> Tab {
        let tab = makeTab(url: url)
        (space ?? activeSpace).todayTabs.insert(tab, at: 0)
        extensions?.controller.didOpenTab(tab)
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

    // MARK: Peek

    /// Like Arc: ⇧-clicked links open in Peek, and so do links from a pinned tab or favorite to
    /// another site, so the pinned page stays where it was. `leavesPage` is false for links
    /// navigating a frame inside the page.
    func opensInPeek(_ url: URL, clickedIn tab: Tab, target: LinkTarget, leavesPage: Bool) -> Bool {
        guard tab !== peek, url.isWebPage else { return false }
        switch target {
        case .peek: return true
        case .newTab: return false
        case .asRequested:
            return leavesPage && tab.isPinned && preferences.opensPinnedLinksInPeek && !url.isSameSite(as: tab.url)
        }
    }

    /// Replaces the page already peeking, if any.
    func openPeek(_ url: URL, from opener: Tab) {
        closePeek()
        let tab = makeTab(url: url)
        tab.opener = opener
        isFindBarVisible = false
        peek = tab
    }

    func closePeek() {
        guard let tab = peek else { return }
        peek = nil
        isFindBarVisible = false
        denyPermissionRequests(from: tab)
        // The card shrinks away showing the page; unloading at once would blank it first.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            tab.unload()
        }
    }

    /// Splitting needs the page it came from to belong to a space: favorites are shared by every space.
    var canExpandPeekIntoSplitView: Bool {
        peek?.opener.flatMap(space(containing:)) != nil
    }

    /// Keeps the peeked page as a today tab, beside the page it came from when `intoSplitView`.
    func expandPeek(intoSplitView: Bool = false) {
        guard let tab = peek else { return }
        peek = nil
        let opener = tab.opener
        let space = opener.flatMap(space(containing:)) ?? activeSpace
        space.todayTabs.insert(tab, at: 0)
        extensions?.controller.didOpenTab(tab)
        if intoSplitView, let opener, canSplit(opener, with: tab) {
            splitView(opener, with: tab)
        } else {
            select(tab)
        }
    }

    // MARK: Split view

    /// The split on screen, if the active tab is in one.
    var activeSplit: TabSplit? { activeSpace.split(containing: activeTabID) }

    /// The tabs on screen, leading pane first.
    var visibleTabs: [Tab] {
        if let split = activeSplit,
           let leading = activeSpace.tab(withID: split.leading),
           let trailing = activeSpace.tab(withID: split.trailing) {
            return [leading, trailing]
        }
        return activeTab.map { [$0] } ?? []
    }

    /// Only tabs of the same space split: favorites are shared by every space.
    func canSplit(_ tab: Tab, with other: Tab) -> Bool {
        guard tab !== other, let space = space(containing: tab) else { return false }
        return space.contains(other)
    }

    /// Shows `other` on `side` of `tab` and focuses it; either leaves the split it was in.
    /// Replacing a pane keeps the split's widths.
    func splitView(_ tab: Tab, with other: Tab, on side: SplitSide = .trailing) {
        guard canSplit(tab, with: other), let space = space(containing: tab) else { return }
        let ratio = space.split(containing: tab.id)?.ratio ?? 0.5
        separate(tab)
        separate(other)
        let (leading, trailing) = side == .trailing ? (tab, other) : (other, tab)
        space.splits.append(TabSplit(leading: leading.id, trailing: trailing.id, ratio: ratio))
        select(other)
    }

    /// The tab that stays on screen when `tab` is dragged onto `side` of the page: the other pane
    /// of a split view, or the page shown. `nil` when the drop can't split.
    func tabKept(droppingTab tab: Tab, on side: SplitSide) -> Tab? {
        let shown = visibleTabs
        guard !shown.contains(tab) else { return nil }
        let kept = shown.count == 2 ? (side == .leading ? shown[1] : shown[0]) : activeTab
        guard let kept, canSplit(kept, with: tab) else { return nil }
        return kept
    }

    /// Both tabs stay open as separate rows.
    func separate(_ tab: Tab) {
        for space in spaces where space.split(containing: tab.id) != nil {
            space.splits.removeAll { $0.contains(tab.id) }
            scheduleSave()
        }
    }

    func setSplitRatio(_ ratio: Double) {
        guard let index = activeSpace.splits.firstIndex(where: { $0.contains(activeTabID) }) else { return }
        activeSpace.splits[index].ratio = min(max(ratio, TabSplit.ratioRange.lowerBound), TabSplit.ratioRange.upperBound)
        scheduleSave()
    }

    /// Clicking into a pane makes its tab the active one.
    func focusPane(of tab: Tab) {
        guard tab.id != activeTabID, activeSplit?.contains(tab.id) == true else { return }
        select(tab)
    }

    /// Selecting a tab from another space switches to that space.
    func select(_ tab: Tab?) {
        let previous = activeTab
        visibleTabs.forEach { $0.wasShown(at: .now) }
        if let tab, let owner = space(containing: tab), owner.id != activeSpaceID {
            activeSpaceID = owner.id
        }
        if tab?.id != activeTabID {
            isFindBarVisible = false
            closePeek()
        }
        activeSpace.activeTabID = tab?.id
        activeTabDidChange(from: previous)
        scheduleSave()
    }

    /// `chrome.tabs.onActivated` fires from this, so extensions follow the tab on screen.
    private func activeTabDidChange(from previous: Tab?) {
        guard let extensions, let tab = activeTab, tab !== previous else { return }
        extensions.controller.didActivateTab(tab, previousActiveTab: previous)
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
        if tab === peek {
            closePeek()
            return
        }
        if tab === peek?.opener { closePeek() }
        let previous = activeTab
        denyPermissionRequests(from: tab)
        // Closing one pane of a split view leaves the other on screen, like Arc.
        let partner = space(containing: tab).flatMap { space in
            space.split(containing: tab.id)?.partner(of: tab.id).flatMap(space.tab(withID:))
        }
        separate(tab)
        if tab.isPinned {
            tab.resetToPinnedURL()
            if tab.id == activeTabID { select(partner ?? todayTabs.first) }
        } else if let space = space(containing: tab),
                  let index = space.todayTabs.firstIndex(where: { $0.id == tab.id }) {
            space.todayTabs.remove(at: index)
            extensions?.controller.didCloseTab(tab, windowIsClosing: false)
            tab.unload()
            if tab.url.absoluteString != "about:blank" {
                closedTabs.append(ClosedTab(url: tab.url, title: tab.title, spaceID: space.id, index: index))
            }
            if space.activeTabID == tab.id {
                if space.id == activeSpaceID { isFindBarVisible = false }
                // Like Chrome, closing a popup or a link opened in a new tab returns to the page that opened it.
                let opener = tab.opener.flatMap { opener in
                    (favorites(in: space.profileID) + space.tabs).first { $0 === opener }
                }
                let neighbor = space.todayTabs.indices.contains(index) ? space.todayTabs[index] : space.todayTabs.last
                space.activeTabID = (partner ?? opener ?? neighbor)?.id
            }
        }

        if activeTab == nil {
            commandBar = .newTab
        }
        activeTabDidChange(from: previous)
        scheduleSave()
    }

    /// Opens the same page in a new today tab right below it (at the top for favorites and pinned tabs).
    func duplicate(_ tab: Tab) {
        let copy = makeTab(url: tab.url, title: tab.title)
        copy.customTitle = tab.customTitle
        let space = space(containing: tab) ?? activeSpace
        let index = space.todayTabs.firstIndex { $0.id == tab.id }.map { $0 + 1 } ?? 0
        space.todayTabs.insert(copy, at: index)
        extensions?.controller.didOpenTab(copy)
        select(copy)
    }

    /// Closes the today tabs under `tab` in its space, like Arc's "Close Tabs Below".
    func closeTabs(below tab: Tab) {
        guard let space = space(containing: tab), let index = space.todayTabs.firstIndex(where: { $0.id == tab.id })
        else { return }
        space.todayTabs[(index + 1)...].forEach(close)
    }

    /// Closes every other today tab in `tab`'s space; favorites and pinned tabs stay.
    func closeOtherTabs(than tab: Tab) {
        guard let space = space(containing: tab) else { return }
        space.todayTabs.filter { $0.id != tab.id }.forEach(close)
    }

    /// Closed one by one so each can be reopened with ⌘⇧T.
    func closeTodayTabs(in space: Space) {
        space.todayTabs.forEach(close)
    }

    /// Makes the page a pinned tab or favorite has navigated to the one it resets to.
    func updatePinnedURL(of tab: Tab) {
        guard tab.isPinned else { return }
        tab.pinnedURL = tab.url
        scheduleSave()
    }

    // MARK: Memory

    /// Checks every minute for tabs that have been off screen longer than the user's setting.
    func startHibernatingInactiveTabs() {
        guard hibernationTask == nil else { return }
        hibernationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                // Ends with the browser, which private windows release when they close.
                guard let self else { return }
                await hibernateInactiveTabs()
            }
        }
    }

    /// Puts tabs to sleep, like Chrome's Memory Saver, except the one on screen and any that are busy.
    func hibernateInactiveTabs(now: Date = .now) async {
        guard let delay = preferences.tabSleepDelay.duration else { return }
        let shownTabs = visibleTabs
        shownTabs.forEach { $0.wasShown(at: now) }
        for tab in tabsInAllProfiles where !shownTabs.contains(tab) && now.timeIntervalSince(tab.lastShown) >= delay {
            // Checked last: it asks the web process, and the tab may be shown again meanwhile.
            if await tab.canHibernate(), !visibleTabs.contains(tab) { tab.hibernate() }
        }
    }

    /// Removes the cookies and storage of the tab's site (signing the user out) and reloads it.
    func clearSiteData(for tab: Tab) async {
        guard let host = tab.url.host(), let site = tab.url.displayHost else { return }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let dataStore = dataStore(for: tab)
        // Records are named by registrable domain, e.g. `google.com` for `mail.google.com`.
        let records = await dataStore.dataRecords(ofTypes: types).filter {
            host == $0.displayName || host.hasSuffix("." + $0.displayName)
        }
        await dataStore.removeData(ofTypes: types, for: records)
        tab.reload()
        showToast("Cleared Data for \(site)")
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

    // MARK: Content blocking

    /// Applies new lists, or a changed setting, to every page that's loaded.
    func contentRulesDidChange() {
        tabsInAllProfiles.forEach { $0.applyContentRules(forPageAt: $0.url) }
    }

    /// Allows or blocks ads on the tab's site and reloads it, so the page shows the change.
    func toggleContentBlocking(on tab: Tab) {
        guard let site = tab.url.displayHost else { return }
        let isBlocking = !contentBlocker.isBlocking(on: tab.url)
        contentBlocker.setBlocking(isBlocking, onSite: site)
        tab.reload()
        showToast(isBlocking ? "Blocking Ads on \(site)" : "Allowed Ads on \(site)")
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

    // MARK: Onboarding and import

    func showWhatsNew() {
        commandBar = nil
        openTab(url: InternalPage.whatsNew.url)
    }

    /// Opens What's New on the first launch after an update that has highlights; a fresh install
    /// only records the version, since onboarding already introduces Pulse.
    func announceUpdate(to appVersion: String, releases: [ReleaseNotes]) {
        let lastSeenVersion = preferences.lastSeenVersion
        preferences.lastSeenVersion = appVersion
        let isUpdate = lastSeenVersion.map { $0.compare(appVersion, options: .numeric) == .orderedAscending }
            ?? preferences.hasCompletedOnboarding
        // Look at every release since the last one seen, so skipping a minor for its patch still announces it.
        let hasUnseenHighlights = releases.contains { release in
            !release.highlights.isEmpty
                && release.version.compare(appVersion, options: .numeric) != .orderedDescending
                && lastSeenVersion.map { release.version.compare($0, options: .numeric) == .orderedDescending } ?? true
        }
        guard isUpdate, hasUnseenHighlights else { return }
        openTab(url: InternalPage.whatsNew.url)
    }

    func showChromeImport() {
        isChromeImportPresented = true
    }

    /// Called however the onboarding closes, so it never shows again.
    func finishOnboarding() {
        isOnboardingPresented = false
        preferences.hasCompletedOnboarding = true
        if activeTab == nil { commandBar = .newTab }
    }

    /// Reads everything first, so a failure leaves the browser unchanged.
    /// Cookies go to `cookieStore`, the one every tab shares unless a test passes its own.
    func importFromChrome(
        _ profile: ChromeProfile,
        items: ChromeImportItems,
        cookieStore: WKHTTPCookieStore = WKWebsiteDataStore.default().httpCookieStore
    ) async throws -> ChromeImportSummary {
        let bookmarks = items.contains(.bookmarks) ? try ChromeImport.bookmarkBar(of: profile) : []
        let cookies = items.contains(.cookies) ? try ChromeImport.cookies(of: profile) : []
        var summary = ChromeImportSummary()
        if items.contains(.history) {
            guard let history else { throw ChromeImportError.unreadableHistory }
            let imported = try ChromeImport.withHistoryCopy(of: profile) { history.importChromeHistory(from: $0) }
            guard imported else { throw ChromeImportError.unreadableHistory }
            summary.importedHistory = true
        }
        for cookie in cookies {
            await cookieStore.setCookie(cookie)
        }
        summary.cookieCount = cookies.count
        if !bookmarks.isEmpty {
            createSpace(named: "Chrome", pinning: bookmarks)
            summary.bookmarkCount = bookmarks.count
        }
        return summary
    }

    // MARK: Permissions

    /// The prompt to show: the oldest request from the visible tab.
    var activePermissionRequest: PermissionRequest? {
        permissionRequests.first { $0.tabID == focusedTab?.id }
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

    /// The site controls' switch: remembered like the prompt's "Allow while visiting the site" or
    /// "Never allow", and turning it off also stops the camera or microphone if the page is using it.
    func setPermission(_ isAllowed: Bool, for kind: PermissionKind, on tab: Tab) {
        if let origin = tab.url.permissionOrigin {
            sitePermissions?.setDecision(isAllowed, for: origin, kind: kind)
        }
        if !isAllowed { tab.stopCapture(kind) }
    }

    private func denyPermissionRequests(from tab: Tab) {
        let pending = permissionRequests.filter { $0.tabID == tab.id }
        permissionRequests.removeAll { $0.tabID == tab.id }
        pending.forEach { $0.respond(.deny) }
    }

    /// ⌘W closes Peek first, like Arc.
    func closeActiveTab() {
        if let tab = focusedTab { close(tab) }
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
        extensions?.controller.didOpenTab(tab)
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
        let wasPinned = tab.isPinned
        let previousProfileID = profileID(of: tab)
        guard detach(tab) else { return }
        // Favorites belong to every space; a split stays within one.
        if destination.section == .favorites { separate(tab) }
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
        if tab.isPinned != wasPinned { extensions?.controller.didChangeTabProperties(.pinned, for: tab) }
        if profileID(of: tab) != previousProfileID { tab.restartWebView() }
        scheduleSave()
    }

    /// Moves a tab to the top of another space's today tabs and follows it there.
    func moveTab(_ tab: Tab, to space: Space) {
        let previousProfileID = profileID(of: tab)
        guard detach(tab) else { return }
        separate(tab)
        tab.pinnedURL = nil
        space.todayTabs.insert(tab, at: 0)
        if space.profileID != previousProfileID { tab.restartWebView() }
        select(tab)
    }

    /// An empty title restores the page's own title.
    func rename(_ tab: Tab, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        tab.customTitle = trimmed.isEmpty ? nil : trimmed
        scheduleSave()
    }

    private func detach(_ tab: Tab) -> Bool {
        if let profileID = profileID(ofFavorite: tab) {
            favoritesByProfile[profileID]?.removeAll { $0.id == tab.id }
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
        let space = Space(name: "Space \(spaces.count + 1)", theme: nextSpaceTheme)
        spaces.append(space)
        selectSpace(space)
        commandBar = .newTab
        return space
    }

    /// A new space with `bookmarks` as its pinned tabs, e.g. imported from another browser.
    @discardableResult
    func createSpace(named name: String, pinning bookmarks: [Bookmark]) -> Space {
        let pinnedTabs = bookmarks.map { bookmark in
            let tab = makeTab(url: bookmark.url, title: bookmark.title)
            tab.pinnedURL = bookmark.url
            tab.loadFavicon()
            return tab
        }
        let space = Space(name: name, theme: nextSpaceTheme, pinnedTabs: pinnedTabs)
        spaces.append(space)
        selectSpace(space)
        return space
    }

    /// Shows Arc's "Create a Space" form in place of the sidebar.
    func beginCreatingSpace() {
        commandBar = nil
        isSidebarExpanded = true
        if spaceDraft == nil {
            spaceDraft = Space(name: "", theme: nextSpaceTheme)
        }
    }

    func cancelCreatingSpace() {
        spaceDraft = nil
    }

    /// Adds the draft as a new space; does nothing while it has no name.
    @discardableResult
    func commitSpaceDraft() -> Space? {
        guard let draft = spaceDraft else { return nil }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        draft.name = name
        spaceDraft = nil
        spaces.append(draft)
        selectSpace(draft)
        commandBar = .newTab
        return draft
    }

    /// The theme the sidebar is painted with, previewing the draft's while one is being created.
    var sidebarTheme: SpaceTheme {
        spaceDraft?.theme ?? activeSpace.theme
    }

    private var nextSpaceTheme: SpaceTheme {
        SpaceTheme.allCases[spaces.count % SpaceTheme.allCases.count]
    }

    func selectSpace(_ space: Space) {
        spaceDraft = nil
        guard space.id != activeSpaceID, spaces.contains(where: { $0.id == space.id }) else { return }
        let previous = activeTab
        previous?.wasShown(at: .now)
        closePeek()
        activeSpaceID = space.id
        isFindBarVisible = false
        commandBar = nil
        activeTabDidChange(from: previous)
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

    func beginEditingIcon(of space: Space) {
        editingIconSpaceID = space.id
    }

    func endEditingIcon() {
        editingIconSpaceID = nil
    }

    /// `nil` brings back the color dot.
    func setIcon(_ icon: String?, for space: Space) {
        space.icon = icon
        scheduleSave()
    }

    /// Moves the space to `index` in the switcher, which also renumbers the ⌃1–⌃9 shortcuts.
    func moveSpace(_ space: Space, to index: Int) {
        guard let source = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        let destination = min(max(index, 0), spaces.count - 1)
        guard destination != source else { return }
        spaces.remove(at: source)
        spaces.insert(space, at: destination)
        scheduleSave()
    }

    /// Closes the space's pinned and today tabs; favorites stay. The last space can't be deleted.
    func delete(_ space: Space) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        let previous = activeTab
        spaces.remove(at: index)
        for tab in space.tabs {
            extensions?.controller.didCloseTab(tab, windowIsClosing: false)
            tab.unload()
        }
        if activeSpaceID == space.id {
            closePeek()
            activeSpaceID = spaces[min(index, spaces.count - 1)].id
            isFindBarVisible = false
        }
        activeTabDidChange(from: previous)
        scheduleSave()
    }

    // MARK: Profiles

    /// Where the tab's cookies and site data live. A tab in a space or the favorites uses its
    /// profile's; Peek and pages not added anywhere yet use their opener's, or the active space's.
    func dataStore(for tab: Tab) -> WKWebsiteDataStore {
        dataStore(for: profileID(of: tab))
    }

    func dataStore(for profileID: Profile.ID) -> WKWebsiteDataStore {
        if let privateDataStore { return privateDataStore }
        if profileID == Profile.defaultID { return .default() }
        if let dataStore = profileDataStores[profileID] { return dataStore }
        let dataStore = WKWebsiteDataStore(forIdentifier: profileID)
        profileDataStores[profileID] = dataStore
        return dataStore
    }

    /// Every profile's, for clearing browsing data everywhere.
    var allDataStores: [WKWebsiteDataStore] {
        privateDataStore.map { [$0] } ?? profiles.map { dataStore(for: $0.id) }
    }

    func profileID(of tab: Tab) -> Profile.ID {
        if let space = space(containing: tab) { return space.profileID }
        if let profileID = profileID(ofFavorite: tab) { return profileID }
        if let opener = tab.opener { return profileID(of: opener) }
        return activeSpace.profileID
    }

    private func profileID(ofFavorite tab: Tab) -> Profile.ID? {
        favoritesByProfile.first { $0.value.contains { $0.id == tab.id } }?.key
    }

    func profile(withID id: Profile.ID) -> Profile? {
        profiles.first { $0.id == id }
    }

    /// Does nothing without a name.
    @discardableResult
    func createProfile(named name: String) -> Profile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let profile = Profile(id: UUID(), name: trimmed)
        profiles.append(profile)
        scheduleSave()
        return profile
    }

    /// The default profile keeps its name.
    func rename(_ profile: Profile, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.isDefault, !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == profile.id })
        else { return }
        profiles[index].name = trimmed
        scheduleSave()
    }

    /// The space's tabs reload in the new profile, signed in as it is; favorites change with it.
    func setProfile(_ profileID: Profile.ID, for space: Space) {
        guard space.profileID != profileID, profile(withID: profileID) != nil else { return }
        let previous = activeTab
        if space.id == activeSpaceID { closePeek() }
        space.profileID = profileID
        space.tabs.forEach { $0.restartWebView() }
        // The old profile's favorite it was showing isn't in its sidebar anymore.
        repairActiveTab(of: space)
        if space.id == activeSpaceID, activeTab == nil { commandBar = .newTab }
        activeTabDidChange(from: previous)
        scheduleSave()
    }

    /// Its spaces and favorites move to the default profile; its cookies and site data are deleted.
    func delete(_ profile: Profile) {
        guard !profile.isDefault, profiles.contains(where: { $0.id == profile.id }) else { return }
        let previous = activeTab
        closePeek()
        let movedFavorites = favoritesByProfile.removeValue(forKey: profile.id) ?? []
        favoritesByProfile[Profile.defaultID, default: []] += movedFavorites
        let movedSpaces = spaces.filter { $0.profileID == profile.id }
        movedSpaces.forEach { $0.profileID = Profile.defaultID }
        (movedFavorites + movedSpaces.flatMap(\.tabs)).forEach { $0.restartWebView() }
        profiles.removeAll { $0.id == profile.id }
        profileDataStores[profile.id] = nil
        activeTabDidChange(from: previous)
        scheduleSave()
        guard privateDataStore == nil else { return }
        Task {
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: profile.id)
            } catch {
                // Pages that just closed may still hold it; the next launch removes it.
                Logger.session.error("Couldn't delete profile data yet: \(error.localizedDescription)")
            }
        }
    }

    /// Deletes the data of profiles deleted while WebKit still had it in use.
    func removeDeletedProfilesData() async {
        guard didRestoreSession, privateDataStore == nil else { return }
        let profileIDs = Set(profiles.map(\.id))
        for identifier in await WKWebsiteDataStore.allDataStoreIdentifiers where !profileIDs.contains(identifier) {
            try? await WKWebsiteDataStore.remove(forIdentifier: identifier)
        }
    }

    func copyURL(of tab: Tab) {
        copy(tab.url, toast: "Copied Current URL")
    }

    func copyLink(_ url: URL) {
        copy(url, toast: "Copied Link")
    }

    private func copy(_ url: URL, toast message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showToast(message, sharing: url)
    }

    // MARK: Command bar

    func showCommandBar(_ mode: CommandBarMode) {
        commandBar = mode != .newTab && activeTab == nil ? .newTab : mode
    }

    func dismissCommandBar() {
        commandBar = nil
    }

    /// `isTyped` marks addresses the user typed, which Chrome ranks first in suggestions.
    func open(_ url: URL, from mode: CommandBarMode, isTyped: Bool = false) {
        if isTyped { history?.recordTyped(url) }
        commandBar = nil
        switch mode {
        case .editActiveTab where activeTab != nil:
            activeTab?.load(url)
        case .splitView:
            let tab = openTab(url: url, activate: false)
            if let activeTab, canSplit(activeTab, with: tab) {
                splitView(activeTab, with: tab)
            } else {
                select(tab)
            }
        default:
            openTab(url: url)
        }
    }

    func switchTo(_ tab: Tab, from mode: CommandBarMode) {
        commandBar = nil
        if mode == .splitView, let activeTab, canSplit(activeTab, with: tab) {
            splitView(activeTab, with: tab)
        } else {
            select(tab)
        }
    }

    // MARK: Find

    func showFindBar() {
        guard focusedTab != nil else { return }
        isFindBarVisible = true
        findBarActivation += 1
    }

    func hideFindBar() {
        isFindBarVisible = false
        isFindQueryMissing = false
        focusedTab?.clearFindSelection()
    }

    func findInPage(backwards: Bool = false) {
        guard let tab = focusedTab, !findQuery.isEmpty else {
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

    func showToast(_ message: String, sharing sharedURL: URL? = nil) {
        toast = Toast(message: message, sharedURL: sharedURL)
        scheduleToastDismissal()
    }

    /// Hovering holds the toast so its share button stays reachable.
    func setToastHovered(_ isHovered: Bool) {
        if isHovered {
            toastTask?.cancel()
        } else {
            scheduleToastDismissal()
        }
    }

    private func scheduleToastDismissal() {
        toastTask?.cancel()
        // Toasts with an action stay longer so there's time to reach for it.
        let duration: Duration = toast?.sharedURL == nil ? .seconds(1.5) : .seconds(2.5)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Session

    var session: Session {
        Session(
            favorites: favorites(in: Profile.defaultID).map(Session.SavedTab.init),
            spaces: spaces.map { space in
                Session.SavedSpace(
                    id: space.id,
                    name: space.name,
                    theme: space.theme.rawValue,
                    icon: space.icon,
                    pinnedTabs: space.pinnedTabs.map(Session.SavedTab.init),
                    todayTabs: space.todayTabs.map(Session.SavedTab.init),
                    activeTabID: space.activeTabID,
                    splits: space.splits.isEmpty ? nil : space.splits,
                    profileID: space.profileID == Profile.defaultID ? nil : space.profileID
                )
            },
            activeSpaceID: activeSpaceID,
            profiles: profiles.filter { !$0.isDefault }.map { profile in
                Session.SavedProfile(
                    id: profile.id,
                    name: profile.name,
                    favorites: favorites(in: profile.id).map(Session.SavedTab.init)
                )
            }
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
        profiles = [.default] + session.profiles.map { Profile(id: $0.id, name: $0.name) }
        favoritesByProfile[Profile.defaultID] = session.favorites.map(makeTab)
        for saved in session.profiles {
            favoritesByProfile[saved.id] = saved.favorites.map(makeTab)
        }
        let profileIDs = Set(profiles.map(\.id))
        let restoredSpaces = session.spaces.map { saved in
            Space(
                id: saved.id,
                name: saved.name,
                theme: SpaceTheme(rawValue: saved.theme) ?? .purple,
                icon: saved.icon,
                pinnedTabs: saved.pinnedTabs.map(makeTab),
                todayTabs: saved.todayTabs.map(makeTab),
                activeTabID: saved.activeTabID,
                splits: saved.splits ?? [],
                profileID: saved.profileID.flatMap { profileIDs.contains($0) ? $0 : nil } ?? Profile.defaultID
            )
        }
        didRestoreSession = true
        guard let firstSpace = restoredSpaces.first else { return }
        spaces = restoredSpaces
        activeSpaceID = restoredSpaces.first { $0.id == session.activeSpaceID }?.id ?? firstSpace.id

        spaces.forEach(repairActiveTab)
    }

    /// An active tab that no longer belongs to the space's sidebar falls back to its first tab.
    private func repairActiveTab(of space: Space) {
        guard space.activeTabID != nil else { return }
        let favorites = favorites(in: space.profileID)
        if !(favorites + space.tabs).contains(where: { $0.id == space.activeTabID }) {
            space.activeTabID = (space.todayTabs.first ?? space.pinnedTabs.first ?? favorites.first)?.id
        }
    }

    /// "Start with an empty Today": favorites and pinned tabs stay, today tabs are closed.
    private func clearToday() {
        for space in spaces {
            space.todayTabs.removeAll()
            space.removeStaleSplits()
            if !(favorites(in: space.profileID) + space.pinnedTabs).contains(where: { $0.id == space.activeTabID }) {
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
