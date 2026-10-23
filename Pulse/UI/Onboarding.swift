import AppKit
import SwiftUI

/// First launch, like Arc's: a welcome, importing from Chrome, then becoming the default browser.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultBrowserBannerDismissed") private var isDefaultBrowserBannerDismissed = false
    @State private var step = Step.welcome

    private enum Step {
        case welcome, importChrome, defaultBrowser
    }

    var body: some View {
        Group {
            switch step {
            case .welcome:
                welcome
            case .importChrome:
                ChromeImportView(finishTitle: "Continue") {
                    if DefaultBrowser.isDefault { dismiss() } else { step = .defaultBrowser }
                }
            case .defaultBrowser:
                defaultBrowser
            }
        }
        .padding(32)
        .frame(width: 480, height: 400)
        .background(Theme.sidebarGradient(.purple))
        .foregroundStyle(Theme.sidebarText)
        .animation(.snappy, value: step)
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Welcome to Pulse")
                .font(.system(size: 26, weight: .bold))
            Text("Spaces, a command bar and a sidebar that stays out of your way.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .opacity(0.75)
            Spacer()
            Button("Get Started") { step = .importChrome }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }

    private var defaultBrowser: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 48, weight: .light))
            Text("Make Pulse your default browser")
                .font(.system(size: 22, weight: .bold))
            Text("Links you open from other apps will open in Pulse.")
                .font(.system(size: 14))
                .opacity(0.75)
            Spacer()
            HStack {
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
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Picks Chrome's folder and a profile, then imports its history and bookmarks bar.
/// The sandbox only lets Pulse read the folder once the user chooses it in an open panel.
struct ChromeImportView: View {
    let finishTitle: String
    let onFinish: () -> Void

    @Environment(Browser.self) private var browser
    @State private var profiles: [ChromeProfile] = []
    @State private var selectedProfile: ChromeProfile?
    @State private var includesHistory = true
    @State private var includesBookmarks = true
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
                Text("Bring over your history, so the address bar suggests the sites you visit, and your bookmarks bar as pinned tabs.")
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
                }
                .toggleStyle(.checkbox)
                errorText
                Spacer()
                buttons(primary: "Import", action: importSelection)
                    .disabled(!includesHistory && !includesBookmarks)
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

    private func importSelection() {
        guard let selectedProfile else { return }
        do {
            summary = try browser.importFromChrome(selectedProfile, history: includesHistory, bookmarks: includesBookmarks)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
        return parts.isEmpty ? "There was nothing to import." : "Imported \(parts.joined(separator: " and "))."
    }
}
