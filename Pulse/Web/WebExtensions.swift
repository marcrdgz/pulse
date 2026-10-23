import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers
import WebKit

/// Runs browser extensions (Chrome's and Safari's WebExtensions) through WebKit's extension API.
/// Each one is stored in `directory` as a folder or ZIP archive named after its unique identifier:
/// the Chrome Web Store ID when it came from there, so installing it again updates it in place.
@Observable
final class WebExtensions: NSObject {
    enum Source {
        case file(URL)
        case chromeWebStore(id: String)
    }

    /// Loaded extensions, in install order.
    private(set) var contexts: [WKWebExtensionContext] = []
    /// Bumped when an extension changes its action's badge, icon or title, so buttons redraw.
    private(set) var actionRevision = 0

    @ObservationIgnored let controller: WKWebExtensionController
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let defaults: UserDefaults
    /// Only the main window runs extensions; private windows keep them out, like Chrome's default.
    @ObservationIgnored private weak var browser: Browser?
    /// The button the next action popup points at.
    @ObservationIgnored private weak var popupAnchor: NSView?
    /// Chrome's "Add “Name”?" dialog; tests answer for the user.
    @ObservationIgnored var confirmInstall: @MainActor (WKWebExtension) async -> Bool = WebExtensions.askToInstall
    /// Asks before a page (the Chrome Web Store) removes an extension.
    @ObservationIgnored var confirmRemoval: @MainActor (WKWebExtensionContext) async -> Bool = WebExtensions.askToRemove

    /// WebKit doesn't persist what the user granted, so it's kept per extension identifier.
    private enum Key {
        static let grantedPermissions = "webExtensionGrantedPermissions"
        static let grantedMatchPatterns = "webExtensionGrantedMatchPatterns"
    }

    init(directory: URL, defaults: UserDefaults, configuration: WKWebExtensionController.Configuration = .default()) {
        self.directory = directory
        self.defaults = defaults
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
    }

    func register(_ browser: Browser) {
        self.browser = browser
        controller.didOpenWindow(browser)
        controller.didFocusWindow(browser)
    }

    /// Extensions that fail to load (e.g. a manifest WebKit no longer accepts) stay on disk.
    func loadInstalled() async {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                try await load(entry, identifier: entry.deletingPathExtension().lastPathComponent)
            } catch {
                Logger.extensions.error("Failed to load \(entry.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    func context(identifiedBy identifier: String) -> WKWebExtensionContext? {
        contexts.first { $0.uniqueIdentifier == identifier }
    }

    /// The configuration a web view needs to show an extension's own pages, such as its options.
    func webViewConfiguration(forPageAt url: URL) -> WKWebViewConfiguration? {
        controller.extensionContext(for: url)?.webViewConfiguration
    }

    // MARK: Installing

    /// Installs a folder, ZIP archive or CRX package once `confirm` agrees, granting what the
    /// manifest asks for, like Chrome. An installed copy with the same identifier is replaced,
    /// keeping its storage. Returns `nil` when not confirmed.
    @discardableResult
    func install(
        from source: URL,
        identifier: String = UUID().uuidString.lowercased(),
        confirm: @MainActor (WKWebExtension) async -> Bool
    ) async throws -> WKWebExtensionContext? {
        let staging = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let staged = try stage(source, in: staging)
        // Validated before anything installed is touched, so a broken update keeps the old copy.
        let candidate = try await WKWebExtension(resourceBaseURL: staged)
        // WebKit loads incomplete manifests too, only listing what's wrong (even a missing description),
        // so the keys Chrome requires are checked here.
        guard candidate.manifest["manifest_version"] != nil, candidate.displayName != nil, candidate.version != nil else {
            throw candidate.errors.first ?? WKWebExtension.Error(.invalidManifest)
        }
        guard await confirm(candidate) else { return nil }

        if let installed = context(identifiedBy: identifier) {
            try? controller.unload(installed)
            contexts.removeAll { $0 === installed }
        }
        removeFiles(of: identifier)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: staged.hasDirectoryPath ? identifier : identifier + ".zip")
        try FileManager.default.moveItem(at: staged, to: destination)
        return try await load(destination, identifier: identifier, grantingRequestedPermissions: true)
    }

    /// Installs with Chrome's confirmation dialog, reporting the result to the user.
    /// Returns whether the extension was installed.
    @discardableResult
    func install(_ source: Source) async -> Bool {
        do {
            let context: WKWebExtensionContext?
            switch source {
            case .file(let url):
                context = try await install(from: url, confirm: confirmInstall)
            case .chromeWebStore(let id):
                let (package, response) = try await URLSession.shared.download(from: ChromeWebStore.packageURL(forExtension: id))
                defer { try? FileManager.default.removeItem(at: package) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                context = try await install(from: package, identifier: id, confirm: confirmInstall)
            }
            guard let context else { return false }
            browser?.showToast("Added \(context.webExtension.displayName ?? "Extension")")
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't add the extension"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
    }

    /// Like Chrome's "Load unpacked", but also takes packed extensions.
    func chooseAndInstall() {
        let panel = NSOpenPanel()
        panel.message = "Choose an extension folder, ZIP archive or CRX package."
        panel.prompt = "Install"
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.folder, .zip, UTType(filenameExtension: "crx") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await install(.file(url)) }
    }

    /// Removes the extension along with everything it stored.
    func uninstall(_ context: WKWebExtensionContext) async {
        let types = WKWebExtensionController.allExtensionDataTypes
        if let record = await controller.dataRecord(ofTypes: types, for: context) {
            await controller.removeData(ofTypes: types, from: [record])
        }
        try? controller.unload(context)
        contexts.removeAll { $0 === context }
        removeFiles(of: context.uniqueIdentifier)
        setGrants(nil, forKey: Key.grantedPermissions, of: context.uniqueIdentifier)
        setGrants(nil, forKey: Key.grantedMatchPatterns, of: context.uniqueIdentifier)
    }

    func openOptionsPage(of context: WKWebExtensionContext) {
        guard let url = context.optionsPageURL else { return }
        browser?.openTab(url: url)
    }

    /// Runs the extension's toolbar action on `tab`; its popup, if any, points at `anchor`.
    func performAction(of context: WKWebExtensionContext, in tab: Tab?, from anchor: NSView?) {
        popupAnchor = anchor
        context.performAction(for: tab)
    }

    /// Chrome's wording for what an extension can do, most powerful first.
    static func permissionDescriptions(
        for permissions: Set<WKWebExtension.Permission>,
        matchPatterns: Set<WKWebExtension.MatchPattern>
    ) -> [String] {
        var descriptions: [String] = []
        if matchPatterns.contains(where: { $0.matchesAllURLs || $0.matchesAllHosts }) {
            descriptions.append("Read and change all your data on all websites")
        } else {
            let hosts = Set(matchPatterns.compactMap { $0.host?.replacing("*.", with: "") }).sorted()
            switch hosts.count {
            case 0: break
            case 1: descriptions.append("Read and change your data on \(hosts[0])")
            case 2: descriptions.append("Read and change your data on \(hosts[0]) and \(hosts[1])")
            default: descriptions.append("Read and change your data on \(hosts[0]), \(hosts[1]) and \(hosts.count - 2) other sites")
            }
        }
        if !permissions.isDisjoint(with: [.tabs, .webNavigation]) {
            descriptions.append("Read your browsing history")
        }
        if !permissions.isDisjoint(with: [.declarativeNetRequest, .declarativeNetRequestWithHostAccess]) {
            descriptions.append("Block content on any page")
        }
        if permissions.contains(.clipboardWrite) {
            descriptions.append("Modify data you copy and paste")
        }
        if permissions.contains(.nativeMessaging) {
            descriptions.append("Communicate with cooperating native applications")
        }
        return descriptions
    }

    private static func askToInstall(_ webExtension: WKWebExtension) async -> Bool {
        let abilities = permissionDescriptions(
            for: webExtension.requestedPermissions,
            matchPatterns: webExtension.requestedPermissionMatchPatterns.union(webExtension.allRequestedMatchPatterns)
        )
        let alert = NSAlert()
        alert.messageText = "Add “\(webExtension.displayName ?? "Extension")”?"
        alert.informativeText = abilities.isEmpty
            ? "It doesn't need any special permissions."
            : "It can:\n" + abilities.map { "• " + $0 }.joined(separator: "\n")
        alert.icon = webExtension.icon(for: CGSize(width: 64, height: 64))
        alert.addButton(withTitle: "Add Extension")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func askToRemove(_ context: WKWebExtensionContext) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Remove “\(context.webExtension.displayName ?? "Extension")”?"
        alert.icon = context.webExtension.icon(for: CGSize(width: 64, height: 64))
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func askToAllow(_ abilities: [String], for context: WKWebExtensionContext) -> Bool {
        let alert = NSAlert()
        alert.messageText = "“\(context.webExtension.displayName ?? "An extension")” wants more access"
        alert.informativeText = "It will be able to:\n" + abilities.map { "• " + $0 }.joined(separator: "\n")
        alert.icon = context.webExtension.icon(for: CGSize(width: 64, height: 64))
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Storage

    private func stage(_ source: URL, in staging: URL) throws -> URL {
        if (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let copy = staging.appending(path: "extension", directoryHint: .isDirectory)
            try FileManager.default.copyItem(at: source, to: copy)
            return copy
        }
        let data = try Data(contentsOf: source)
        let archive = staging.appending(path: "extension.zip")
        try (ChromeWebStore.isPackage(data) ? ChromeWebStore.zipArchive(fromPackage: data) : data).write(to: archive)
        return archive
    }

    @discardableResult
    private func load(
        _ resourceURL: URL,
        identifier: String,
        grantingRequestedPermissions: Bool = false
    ) async throws -> WKWebExtensionContext {
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: resourceURL))
        context.uniqueIdentifier = identifier
        // A stable origin across launches, or the extension's pages lose their local storage.
        context.baseURL = URL(string: "webkit-extension://\(identifier)/")!
        context.isInspectable = true
        if grantingRequestedPermissions {
            let webExtension = context.webExtension
            for permission in webExtension.requestedPermissions {
                context.setPermissionStatus(.grantedExplicitly, for: permission)
            }
            for pattern in webExtension.requestedPermissionMatchPatterns.union(webExtension.allRequestedMatchPatterns) {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
            saveGrants(of: context)
        } else {
            restoreGrants(of: context)
        }
        try controller.load(context)
        contexts.append(context)
        return context
    }

    private func removeFiles(of identifier: String) {
        for name in [identifier, identifier + ".zip"] {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    private func saveGrants(of context: WKWebExtensionContext) {
        let identifier = context.uniqueIdentifier
        setGrants(context.grantedPermissions.keys.map(\.rawValue), forKey: Key.grantedPermissions, of: identifier)
        setGrants(context.grantedPermissionMatchPatterns.keys.map(\.string), forKey: Key.grantedMatchPatterns, of: identifier)
    }

    private func restoreGrants(of context: WKWebExtensionContext) {
        let identifier = context.uniqueIdentifier
        for permission in grants(forKey: Key.grantedPermissions, of: identifier) {
            context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: permission))
        }
        for string in grants(forKey: Key.grantedMatchPatterns, of: identifier) {
            if let pattern = try? WKWebExtension.MatchPattern(string: string) {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
        }
    }

    private func grants(forKey key: String, of identifier: String) -> [String] {
        (defaults.dictionary(forKey: key) as? [String: [String]])?[identifier] ?? []
    }

    private func setGrants(_ grants: [String]?, forKey key: String, of identifier: String) {
        var all = defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
        all[identifier] = grants
        defaults.set(all, forKey: key)
    }
}

extension WebExtensions: WKWebExtensionControllerDelegate {
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        browser.map { [$0] } ?? []
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        browser
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext
    ) async throws -> (any WKWebExtensionTab)? {
        guard let browser else { return nil }
        let tab = browser.openTab(url: configuration.url ?? URL(string: "about:blank")!, activate: configuration.shouldBeActive)
        if configuration.shouldBePinned { browser.togglePin(tab) }
        if configuration.shouldBeMuted { tab.toggleMuted() }
        return tab
    }

    /// Pulse has a single window, so a new one (e.g. a password manager's pop-out) becomes tabs in it.
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext
    ) async throws -> (any WKWebExtensionWindow)? {
        guard let browser else { return nil }
        for url in configuration.tabURLs {
            browser.openTab(url: url, activate: configuration.shouldBeFocused)
        }
        return browser
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext
    ) async throws {
        openOptionsPage(of: extensionContext)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext
    ) async -> (Set<WKWebExtension.Permission>, Date?) {
        let abilities = Self.permissionDescriptions(for: permissions, matchPatterns: [])
        // Permissions without a warning, like storage, are granted silently, as in Chrome.
        let isAllowed = abilities.isEmpty || Self.askToAllow(abilities, for: extensionContext)
        saveGrantsAfterWebKitApplies(extensionContext)
        return (isAllowed ? permissions : [], nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext
    ) async -> (Set<URL>, Date?) {
        let hosts = Set(urls.compactMap { $0.displayHost }).sorted()
        let isAllowed = Self.askToAllow(["Read and change your data on " + hosts.formatted(.list(type: .and))], for: extensionContext)
        saveGrantsAfterWebKitApplies(extensionContext)
        return (isAllowed ? urls : [], nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext
    ) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        let abilities = Self.permissionDescriptions(for: [], matchPatterns: matchPatterns)
        let isAllowed = Self.askToAllow(abilities, for: extensionContext)
        saveGrantsAfterWebKitApplies(extensionContext)
        return (isAllowed ? matchPatterns : [], nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext context: WKWebExtensionContext
    ) {
        actionRevision += 1
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for context: WKWebExtensionContext
    ) async throws {
        defer { popupAnchor = nil }
        guard let popover = action.popupPopover else { return }
        if let anchor = popupAnchor, anchor.window != nil {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else if let contentView = browser?.window?.contentView {
            // Opened by the extension itself (`action.openPopup()`): point at the sidebar's top.
            let top = contentView.isFlipped ? 40 : contentView.bounds.maxY - 40
            popover.show(relativeTo: NSRect(x: 120, y: top, width: 1, height: 1), of: contentView, preferredEdge: .minY)
        }
    }

    /// WebKit records the answer only after the prompt returns it.
    private func saveGrantsAfterWebKitApplies(_ context: WKWebExtensionContext) {
        Task { saveGrants(of: context) }
    }
}

extension Logger {
    static let extensions = Logger(subsystem: "dev.doblefilo.pulse", category: "Extensions")
}
