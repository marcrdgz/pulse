import AppKit
import SwiftUI

/// The Settings window's panes; stored so other windows can open it on a given pane.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, search, downloads, profiles, privacy, extensions

    static let storageKey = "settingsPane"

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .search: "Search"
        case .downloads: "Downloads"
        case .profiles: "Profiles"
        case .privacy: "Privacy"
        case .extensions: "Extensions"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .search: "magnifyingglass"
        case .downloads: "arrow.down"
        case .profiles: "person.2.fill"
        case .privacy: "hand.raised.fill"
        case .extensions: "puzzlepiece.extension.fill"
        }
    }

    /// What the sidebar's search field matches besides the title: the settings each pane holds.
    private var keywords: [String] {
        switch self {
        case .general: ["default browser", "startup", "peek", "pinned", "memory", "sleep", "tabs"]
        case .search: ["search engine", "suggestions", "address bar"]
        case .downloads: ["location", "finder", "save", "files"]
        case .profiles: ["accounts", "logins", "cookies", "spaces", "favorites", "work", "personal"]
        case .privacy: ["history", "cookies", "cache", "clear browsing data", "ads", "trackers",
                        "permissions", "camera", "microphone"]
        case .extensions: ["install", "chrome web store", "zip", "crx", "options"]
        }
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || ([title] + keywords).contains { $0.localizedStandardContains(query) }
    }
}

/// ⌘, — the options Chrome has in chrome://settings that apply to Pulse, as a native window
/// laid out like System Settings: a searchable list of panes beside the selected one.
struct SettingsView: View {
    @AppStorage(SettingsPane.storageKey) private var pane = SettingsPane.general
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases.filter { $0.matches(query) }, selection: selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    PaneTile(pane: pane)
                }
            }
            .searchable(text: $query, placement: .sidebar)
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(pane.title)
        }
        .frame(width: 720, height: 520)
    }

    /// The list deselects on an empty click; keep the current pane instead of showing nothing.
    private var selection: Binding<SettingsPane?> {
        Binding(get: { pane }, set: { if let newValue = $0 { pane = newValue } })
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .general: GeneralSettings()
        case .search: SearchSettings()
        case .downloads: DownloadSettings()
        case .profiles: ProfileSettings()
        case .privacy: PrivacySettings()
        case .extensions: ExtensionSettings()
        }
    }
}

/// System Settings' coloured icon square, so the sidebar scans by colour as well as by name.
private struct PaneTile: View {
    let pane: SettingsPane

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Theme.settingsTile(pane).gradient)
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

private struct GeneralSettings: View {
    @Environment(Browser.self) private var browser
    @State private var isDefaultBrowser = DefaultBrowser.isDefault

    var body: some View {
        @Bindable var preferences = browser.preferences
        Form {
            Section {
                LabeledContent {
                    if isDefaultBrowser {
                        Label("Default", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Make Default") {
                            Task {
                                await DefaultBrowser.makeDefault()
                                isDefaultBrowser = DefaultBrowser.isDefault
                            }
                        }
                    }
                } label: {
                    Text("Default browser")
                    Text(isDefaultBrowser ? "Links from other apps open in Pulse." : "Links from other apps open in another browser.")
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("On startup")
                    HStack(spacing: 12) {
                        ForEach(StartupBehavior.allCases) { behavior in
                            StartupOption(
                                behavior: behavior,
                                theme: browser.activeSpace.theme,
                                isSelected: preferences.startupBehavior == behavior
                            ) {
                                preferences.startupBehavior = behavior
                            }
                        }
                    }
                    Text("Favorites and pinned tabs always come back.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section {
                Toggle(isOn: $preferences.opensPinnedLinksInPeek) {
                    Text("Open links from pinned tabs in Peek")
                    Text("Links to other sites preview over the page, so the pinned tab stays where it was. ⇧-click any link to peek at it.")
                }
                Picker(selection: $preferences.tabSleepDelay) {
                    ForEach(TabSleepDelay.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Sleep inactive tabs after")
                    Text("Sleeping tabs free their memory and reload where they were. Tabs playing audio or using your camera or microphone stay awake.")
                }
            }
        }
        .settingsPane()
        .onAppear { isDefaultBrowser = DefaultBrowser.isDefault }
    }
}

/// One way to start, drawn as a miniature sidebar in the active space's colours: what you see is
/// what the sidebar looks like after relaunching.
private struct StartupOption: View {
    let behavior: StartupBehavior
    let theme: SpaceTheme
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                miniature
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
                    }
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Text(behavior.title)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var miniature: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.activeTabFill)
                        .frame(width: 22, height: 16)
                }
            }
            bar(width: 0.7)
            bar(width: 0.55)
            Rectangle()
                .fill(Theme.sidebarText.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 2)
            switch behavior {
            case .continueWhereYouLeftOff:
                bar(width: 0.8)
                bar(width: 0.6)
                bar(width: 0.7)
            case .clearToday:
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Theme.sidebarText.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 9)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sidebarGradient(theme))
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.pillFill)
                .frame(width: proxy.size.width * width)
        }
        .frame(height: 9)
    }
}

private struct SearchSettings: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        @Bindable var preferences = browser.preferences
        Form {
            Section {
                Picker(selection: $preferences.searchEngine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                } label: {
                    Text("Search engine")
                    Text("Used for searches from the address bar and the command bar.")
                }
                Toggle(isOn: $preferences.showsSearchSuggestions) {
                    Text("Show search suggestions")
                    Text("Sends what you type in the address bar to \(preferences.searchEngine.name).")
                }
            }
        }
        .settingsPane()
    }
}

private struct DownloadSettings: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        @Bindable var preferences = browser.preferences
        Form {
            Section {
                LabeledContent {
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(URL.downloadsDirectory)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: URL.downloadsDirectory.path))
                            .resizable()
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Downloads")
                            Text("Files save here unless you choose otherwise.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(isOn: $preferences.asksWhereToSaveDownloads) {
                    Text("Ask where to save each file")
                    Text("Choose a folder before each download starts.")
                }
            }
        }
        .settingsPane()
    }
}

private struct ExtensionSettings: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        Form {
            if let extensions = browser.extensions {
                Section {
                    if extensions.contexts.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.secondary)
                            Text("No extensions yet")
                                .fontWeight(.medium)
                            Text("Open an extension's page in the Chrome Web Store and click \"Add to Pulse\", or install a folder, ZIP or CRX file.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 320)
                            Button("Install from File…", action: extensions.chooseAndInstall)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                    ForEach(extensions.contexts, id: \.uniqueIdentifier) { context in
                        let webExtension = context.webExtension
                        HStack(spacing: 10) {
                            if let icon = webExtension.icon(for: CGSize(width: 32, height: 32)) {
                                Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(webExtension.displayName ?? "Extension")
                                        .fontWeight(.medium)
                                    if let version = webExtension.displayVersion {
                                        Text(version)
                                            .font(.footnote)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                if let description = webExtension.displayDescription {
                                    Text(description)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if context.optionsPageURL != nil {
                                Button("Options") { extensions.openOptionsPage(of: context) }
                            }
                            Button("Remove") { Task { await extensions.uninstall(context) } }
                        }
                    }
                } footer: {
                    if !extensions.contexts.isEmpty {
                        HStack {
                            Text("Add more from the Chrome Web Store, or install a folder, ZIP or CRX file.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Install from File…", action: extensions.chooseAndInstall)
                        }
                    }
                }
            }
        }
        .settingsPane()
    }
}

private struct ProfileSettings: View {
    @Environment(Browser.self) private var browser
    @State private var isNewProfilePresented = false

    var body: some View {
        Form {
            Section {
                ForEach(browser.profiles) { profile in
                    ProfileRow(profile: profile, spaces: browser.spaces.filter { $0.profileID == profile.id })
                }
            } footer: {
                Text(Profile.explanation + " Choose a space's profile when you create it, or from its menu in the sidebar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("New Profile…") { isNewProfilePresented = true }
            }
        }
        .settingsPane()
        .newProfileAlert(isPresented: $isNewProfilePresented)
    }
}

/// Renamed in place; the default profile can be neither renamed nor deleted.
private struct ProfileRow: View {
    @Environment(Browser.self) private var browser
    let profile: Profile
    let spaces: [Space]
    @State private var name = ""

    var body: some View {
        LabeledContent {
            if !profile.isDefault {
                Button("Delete…") { confirmDeleting(profile, in: browser) }
            }
        } label: {
            if profile.isDefault {
                Text(profile.name)
            } else {
                TextField("Name", text: $name)
                    .labelsHidden()
                    .onSubmit { browser.rename(profile, to: name) }
                    .onAppear { name = profile.name }
                    .onChange(of: profile.name) { name = profile.name }
            }
            Text(spaces.isEmpty ? "No spaces" : spaces.map(\.name).formatted(.list(type: .and)))
        }
    }
}

private struct PrivacySettings: View {
    @Environment(Browser.self) private var browser
    @State private var sites: [(origin: String, decisions: [PermissionKind: Bool])] = []

    var body: some View {
        let blocker = browser.contentBlocker
        Form {
            Section {
                LabeledContent {
                    Button("Clear Browsing Data…", action: browser.showClearBrowsingData)
                } label: {
                    Text("Browsing data")
                    Text("Delete history, cookies and cached files.")
                }
            }
            Section {
                Toggle(isOn: Binding(get: { blocker.isEnabled }, set: { blocker.setEnabled($0) })) {
                    Text("Block ads and trackers")
                    Text(contentBlockerCaption(lastUpdate: blocker.lastUpdate))
                }
                ForEach(browser.preferences.adsAllowedSites, id: \.self) { site in
                    LabeledContent {
                        Button("Block Ads") { blocker.setBlocking(true, onSite: site) }
                    } label: {
                        Text(site)
                        Text("Ads allowed")
                    }
                }
            } footer: {
                if !browser.preferences.adsAllowedSites.isEmpty {
                    Text("Allow ads on a site from its address bar's menu.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Camera and microphone") {
                if sites.isEmpty {
                    Text("Sites you allow or block appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sites, id: \.origin) { site in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(site.origin)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Reset") { reset(site.origin) }
                        }
                        ForEach(PermissionKind.allCases, id: \.self) { kind in
                            Picker(selection: binding(site.origin, kind)) {
                                Text("Ask").tag(Bool?.none)
                                Text("Allow").tag(Bool?.some(true))
                                Text("Block").tag(Bool?.some(false))
                            } label: {
                                Label(kind == .camera ? "Camera" : "Microphone", systemImage: kind == .camera ? "video" : "mic")
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .settingsPane()
        .onAppear(perform: reload)
    }

    private func reload() {
        sites = browser.sitePermissions?.allDecisions() ?? []
    }

    private func contentBlockerCaption(lastUpdate: Date?) -> String {
        let lists = "Uses EasyList and EasyPrivacy"
        guard let lastUpdate else { return lists + ", downloaded the first time Pulse runs." }
        return lists + ", updated \(lastUpdate.formatted(.relative(presentation: .named)))."
    }

    private func binding(_ origin: String, _ kind: PermissionKind) -> Binding<Bool?> {
        Binding(
            get: { sites.first { $0.origin == origin }?.decisions[kind] },
            set: { decision in
                browser.sitePermissions?.setDecision(decision, for: origin, kind: kind)
                reload()
            }
        )
    }

    private func reset(_ origin: String) {
        for kind in PermissionKind.allCases {
            browser.sitePermissions?.setDecision(nil, for: origin, kind: kind)
        }
        reload()
    }
}

private extension View {
    func settingsPane() -> some View {
        formStyle(.grouped)
    }
}
