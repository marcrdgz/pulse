import AppKit
import SwiftUI

/// ⌘, — the options Chrome has in chrome://settings that apply to Pulse, as a native window.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            SearchSettings()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            DownloadSettings()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            ExtensionSettings()
                .tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(Browser.self) private var browser
    @State private var isDefaultBrowser = DefaultBrowser.isDefault

    var body: some View {
        @Bindable var preferences = browser.preferences
        Form {
            Section("Default browser") {
                LabeledContent(isDefaultBrowser ? "Pulse is your default browser" : "Pulse isn't your default browser") {
                    if !isDefaultBrowser {
                        Button("Make Default") {
                            Task {
                                await DefaultBrowser.makeDefault()
                                isDefaultBrowser = DefaultBrowser.isDefault
                            }
                        }
                    }
                }
            }
            Section("On startup") {
                Picker("On startup", selection: $preferences.startupBehavior) {
                    ForEach(StartupBehavior.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("Favorites and pinned tabs always come back.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Sleep inactive tabs after", selection: $preferences.tabSleepDelay) {
                    ForEach(TabSleepDelay.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Memory")
            } footer: {
                Text("Sleeping tabs free their memory and reload where they were when you return. "
                    + "Tabs playing audio or using your camera or microphone stay awake.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPane()
        .onAppear { isDefaultBrowser = DefaultBrowser.isDefault }
    }
}

private struct SearchSettings: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        @Bindable var preferences = browser.preferences
        Form {
            Section {
                Picker("Search engine", selection: $preferences.searchEngine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Show search suggestions", isOn: $preferences.showsSearchSuggestions)
            } footer: {
                Text("Suggestions send what you type in the address bar to \(preferences.searchEngine.name).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                LabeledContent("Location") {
                    HStack {
                        Text("Downloads")
                        Button("Show in Finder") {
                            NSWorkspace.shared.open(URL.downloadsDirectory)
                        }
                    }
                }
                Toggle("Ask where to save each file before downloading", isOn: $preferences.asksWhereToSaveDownloads)
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
                        Text("Extensions you add appear here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(extensions.contexts, id: \.uniqueIdentifier) { context in
                        let webExtension = context.webExtension
                        HStack(spacing: 10) {
                            if let icon = webExtension.icon(for: CGSize(width: 32, height: 32)) {
                                Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(webExtension.displayName ?? "Extension")
                                    .fontWeight(.medium)
                                Text([webExtension.displayVersion, webExtension.displayDescription].compactMap(\.self).joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if context.optionsPageURL != nil {
                                Button("Options") { extensions.openOptionsPage(of: context) }
                            }
                            Button("Remove") { Task { await extensions.uninstall(context) } }
                        }
                    }
                } footer: {
                    HStack {
                        Text("Add extensions from their Chrome Web Store page, or install a folder, ZIP or CRX file.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Install from File…", action: extensions.chooseAndInstall)
                    }
                }
            }
        }
        .settingsPane()
    }
}

private struct PrivacySettings: View {
    @Environment(Browser.self) private var browser
    @State private var sites: [(origin: String, decisions: [PermissionKind: Bool])] = []

    var body: some View {
        let blocker = browser.contentBlocker
        Form {
            Section {
                LabeledContent("Delete history, cookies and cache") {
                    Button("Clear Browsing Data…", action: browser.showClearBrowsingData)
                }
            }
            Section {
                Toggle("Block ads and trackers", isOn: Binding(get: { blocker.isEnabled }, set: { blocker.setEnabled($0) }))
                ForEach(browser.preferences.adsAllowedSites, id: \.self) { site in
                    LabeledContent(site) {
                        Button("Block Ads") { blocker.setBlocking(true, onSite: site) }
                    }
                }
            } header: {
                Text("Ads and trackers")
            } footer: {
                Text(contentBlockerFooter(lastUpdate: blocker.lastUpdate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Site permissions") {
                if sites.isEmpty {
                    Text("Sites you allow or block from using your camera or microphone appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sites, id: \.origin) { site in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(site.origin)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Reset") { reset(site.origin) }
                        }
                        ForEach(PermissionKind.allCases, id: \.self) { kind in
                            Picker(kind == .camera ? "Camera" : "Microphone", selection: binding(site.origin, kind)) {
                                Text("Ask").tag(Bool?.none)
                                Text("Allow").tag(Bool?.some(true))
                                Text("Block").tag(Bool?.some(false))
                            }
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

    private func contentBlockerFooter(lastUpdate: Date?) -> String {
        let lists = "Uses EasyList and EasyPrivacy"
        guard let lastUpdate else { return lists + "; they download the first time Pulse runs." }
        return lists + ", updated \(lastUpdate.formatted(.relative(presentation: .named))). "
            + "Sites listed above load ads; allow one from its address bar's menu."
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
    /// Sizes the window to the pane like System Settings, scrolling only once a list outgrows the cap.
    func settingsPane() -> some View {
        formStyle(.grouped)
            .frame(maxHeight: 640)
            .fixedSize(horizontal: false, vertical: true)
    }
}
