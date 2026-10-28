import AppKit
import SwiftUI

extension View {
    /// Asks for a new profile's name and creates it, like Arc's "New Profile…".
    func newProfileAlert(isPresented: Binding<Bool>, onCreate: @escaping (Profile) -> Void = { _ in }) -> some View {
        modifier(NewProfileAlert(isPresented: isPresented, onCreate: onCreate))
    }
}

private struct NewProfileAlert: ViewModifier {
    @Environment(Browser.self) private var browser
    @Binding var isPresented: Bool
    let onCreate: (Profile) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("New Profile", isPresented: $isPresented) {
            TextField("Profile name", text: $name)
            Button("Create") {
                if let profile = browser.createProfile(named: name) { onCreate(profile) }
                name = ""
            }
            Button("Cancel", role: .cancel) { name = "" }
        } message: {
            Text(Profile.explanation)
        }
    }
}

extension Profile {
    static let explanation = "Spaces in different profiles keep separate cookies, logins and favorites."
}

/// Confirms first: the profile's cookies and site data go with it.
@MainActor
func confirmDeleting(_ profile: Profile, in browser: Browser) {
    let alert = NSAlert()
    alert.messageText = "Delete “\(profile.name)”?"
    alert.informativeText = "Its cookies and site data will be deleted, signing you out of its sites. "
        + "Its spaces and favorites move to the Default profile."
    alert.addButton(withTitle: "Delete").hasDestructiveAction = true
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
        browser.delete(profile)
    }
}
