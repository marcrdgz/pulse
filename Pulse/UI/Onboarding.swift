import AppKit
import SwiftUI

/// First launch, in the spirit of Arc's: a welcome, importing from Chrome, a colour for the Home
/// space, the few shortcuts worth knowing, then becoming the default browser. Every step can be
/// skipped, and closing the sheet at any point counts as finishing.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(Browser.self) private var browser
    @AppStorage("defaultBrowserBannerDismissed") private var isDefaultBrowserBannerDismissed = false
    // Decided once, so the step count doesn't change under the progress bar.
    @State private var steps = Step.allCases.filter { $0 != .defaultBrowser || !DefaultBrowser.isDefault }
    @State private var step = Step.welcome

    private enum Step: CaseIterable {
        case welcome, importChrome, theme, essentials, defaultBrowser
    }

    var body: some View {
        VStack(spacing: 24) {
            progress
            Group {
                switch step {
                case .welcome:
                    welcome
                case .importChrome:
                    ChromeImportView(finishTitle: "Continue", onBack: goBack, onFinish: advance)
                        .controlSize(.large)
                case .theme:
                    theme
                case .essentials:
                    essentials
                case .defaultBrowser:
                    defaultBrowser
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(step)
            .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
        }
        .padding(32)
        .frame(width: 560, height: 500)
        .background(Brand.paper)
        .foregroundStyle(Brand.ink)
        .tint(Brand.accent)
        .animation(.snappy, value: step)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            HaloMark(size: 96, drawsIn: true)
            FlareHeadline(text: "Welcome to Pulse.")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.8)
            Text("Spaces for each part of your life, a command bar for everything else, and a sidebar that stays out of your way.")
                .font(.system(size: 15))
                .foregroundStyle(Brand.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Spacer()
            actions {
                Button("Get Started", action: advance)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var theme: some View {
        let space = browser.activeSpace
        return VStack(spacing: 20) {
            title("Make it yours", "Pick a colour for your \(space.name) space. Each space you add can have its own.")
            MiniWindow(theme: space.theme) {
                PageLines()
            } addressAccessory: {
                EmptyView()
            }
            .scaleEffect(0.8)
            .frame(width: 352, height: 176)
            .animation(.snappy, value: space.theme)
            HStack(spacing: 14) {
                ForEach(SpaceTheme.allCases, id: \.self) { theme in
                    ThemeSwatch(theme: theme, isSelected: theme == space.theme) {
                        // The sidebar behind the sheet repaints too, so the choice shows at full size.
                        browser.setTheme(theme, for: space)
                    }
                }
            }
            Spacer(minLength: 0)
            actions {
                Button("Continue", action: advance)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var essentials: some View {
        VStack(spacing: 20) {
            title("A few keys go a long way", "Everything else is in the menus, and in the command bar.")
            VStack(spacing: 0) {
                Essential(keys: ["⌘", "T"], title: "Command bar", detail: "Open a site, search, or jump to any tab.")
                Divider()
                Essential(keys: ["⌘", "S"], title: "Sidebar", detail: "Hide it for a full-width page; it peeks back at the edge.")
                Divider()
                Essential(keys: ["⌃", "1–9"], title: "Spaces", detail: "Switch between spaces, each with its own tabs.")
                Divider()
                Essential(keys: ["⌃", "⇥"], title: "Tabs", detail: "Cycle through the tabs of the space you're in.")
            }
            .padding(.horizontal, 16)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer(minLength: 0)
            actions {
                Button(step == steps.last ? "Start Browsing" : "Continue", action: advance)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var defaultBrowser: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "link")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Brand.accent)
                .frame(width: 88, height: 88)
                .background(Brand.card, in: Circle())
            title("Open links in Pulse", "Make Pulse your default browser, so links from Mail, Slack and other apps land in your sidebar.")
            Spacer()
            actions {
                Button("Not Now") {
                    // Declined here; the banner shouldn't ask again right away.
                    isDefaultBrowserBannerDismissed = true
                    dismiss()
                }
                Button("Make Default") {
                    Task {
                        await DefaultBrowser.makeDefault()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Building blocks

    /// One segment per step, filled up to the current one.
    private var progress: some View {
        let index = steps.firstIndex(of: step) ?? 0
        return HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { position in
                Capsule()
                    .fill(position <= index ? Brand.accent : Brand.line)
                    .frame(width: position == index ? 28 : 14, height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(steps.count)")
    }

    private func title(_ headline: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(headline)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Brand.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    /// Back on the left once there's somewhere to go back to, the step's own buttons on the right.
    private func actions(@ViewBuilder _ trailing: () -> some View) -> some View {
        HStack {
            if step != steps.first {
                Button("Back", action: goBack)
            }
            Spacer()
            trailing()
        }
        .controlSize(.large)
    }

    private func advance() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else {
            dismiss()
            return
        }
        step = steps[index + 1]
    }

    private func goBack() {
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        step = steps[index - 1]
    }
}

private struct ThemeSwatch: View {
    let theme: SpaceTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Theme.sidebarGradient(theme))
                .overlay { Circle().strokeBorder(Theme.swatch(theme), lineWidth: 2) }
                .frame(width: 30, height: 30)
                .padding(4)
                .overlay {
                    Circle().strokeBorder(Brand.ink.opacity(isSelected ? 0.8 : 0), lineWidth: 2)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(theme.displayName)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A shortcut as keycaps, with what it does.
private struct Essential: View {
    let keys: [String]
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(.horizontal, 7)
                        .frame(minWidth: 26, minHeight: 26)
                        .background(Brand.paper, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Brand.line)
                        }
                }
            }
            .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.dim)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

/// Picks Chrome's folder and a profile, then imports its history and bookmarks bar.
struct ChromeImportView: View {
    let finishTitle: String
    /// Shown as a Back button when the import is a step of a longer flow.
    var onBack: (() -> Void)?
    let onFinish: () -> Void

    @Environment(Browser.self) private var browser
    @State private var profiles: [ChromeProfile] = []
    @State private var selectedProfile: ChromeProfile?
    @State private var includesHistory = true
    @State private var includesBookmarks = true
    @State private var includesCookies = false
    @State private var isImporting = false
    @State private var summary: ChromeImportSummary?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import from Chrome")
                .font(.system(size: 20, weight: .bold))
            if let summary {
                Text(summary.message)
                Spacer()
                HStack {
                    Spacer()
                    Button(finishTitle, action: onFinish)
                        .keyboardShortcut(.defaultAction)
                }
            } else if profiles.isEmpty {
                Text("Bring over your history, so the address bar suggests the sites you visit, your bookmarks bar as pinned tabs, and your cookies so you stay signed in.")
                Text("To allow it, choose the “Chrome” folder in the next window.")
                    .opacity(0.75)
                errorText
                Spacer()
                buttons(primary: "Choose Chrome Folder…", action: chooseChromeFolder)
            } else {
                if profiles.count > 1 {
                    Picker("Profile", selection: $selectedProfile) {
                        ForEach(profiles) { profile in
                            Text(profile.email.map { "\(profile.name) (\($0))" } ?? profile.name)
                                .tag(Optional(profile))
                        }
                    }
                    .fixedSize()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("History", isOn: $includesHistory)
                    Toggle("Bookmarks bar, as pinned tabs in a “Chrome” space", isOn: $includesBookmarks)
                    Toggle(isOn: $includesCookies) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Cookies, to stay signed in to sites")
                            Text("macOS asks for your password to let Pulse read them. Choose “Allow”, not “Always Allow”.")
                                .font(.system(size: 11))
                                .opacity(0.75)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                errorText
                Spacer()
                buttons(primary: isImporting ? "Importing…" : "Import", action: importSelection)
                    .disabled(isImporting || selectedItems.isEmpty)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var errorText: some View {
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
        }
    }

    private func buttons(primary: String, action: @escaping () -> Void) -> some View {
        HStack {
            if let onBack {
                Button("Back", action: onBack)
            }
            Spacer()
            Button("Not Now", action: onFinish)
                .keyboardShortcut(.cancelAction)
            Button(primary, action: action)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func chooseChromeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        // Opens on "Google" so "Chrome" is the obvious thing to select.
        panel.directoryURL = ChromeImport.defaultDirectory.deletingLastPathComponent()
        panel.message = "Select the “Chrome” folder so Pulse can import from it."
        panel.prompt = "Allow"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let found = ChromeImport.profiles(in: folder)
        guard !found.isEmpty else {
            errorMessage = "That folder has no Chrome profiles. Choose “Chrome”, inside “Google”."
            return
        }
        profiles = found
        selectedProfile = found.first
        errorMessage = nil
    }

    private var selectedItems: ChromeImportItems {
        var items: ChromeImportItems = []
        if includesHistory { items.insert(.history) }
        if includesBookmarks { items.insert(.bookmarks) }
        if includesCookies { items.insert(.cookies) }
        return items
    }

    private func importSelection() {
        guard let selectedProfile else { return }
        isImporting = true
        Task {
            do {
                summary = try await browser.importFromChrome(selectedProfile, items: selectedItems)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}

private extension ChromeImportSummary {
    var message: String {
        var parts: [String] = []
        if importedHistory { parts.append("your history") }
        if bookmarkCount > 0 {
            let bookmarks = bookmarkCount == 1 ? "1 bookmark" : "\(bookmarkCount) bookmarks"
            parts.append("\(bookmarks) as pinned tabs in the “Chrome” space")
        }
        if cookieCount > 0 {
            parts.append(cookieCount == 1 ? "1 cookie" : "\(cookieCount) cookies")
        }
        return parts.isEmpty ? "There was nothing to import." : "Imported \(parts.formatted(.list(type: .and)))."
    }
}
