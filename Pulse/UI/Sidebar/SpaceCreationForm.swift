import SwiftUI

/// Arc's "Create a Space" form, shown in place of the sidebar. The sidebar previews the draft's
/// theme while it's picked, and the space only exists once it has a name and is created.
struct SpaceCreationForm: View {
    @Environment(Browser.self) private var browser
    @Bindable var draft: Space
    @State private var isThemePickerExpanded = false
    @FocusState private var isNameFocused: Bool

    private var canCreate: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            header
                .padding(.bottom, 8)
            nameField
            themeRow
            Spacer(minLength: 0)
            Button(action: create) {
                Text("Create Space")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                            .fill(Theme.swatch(draft.theme))
                    )
                    .opacity(canCreate ? 1 : 0.5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCreate)
            Button("Cancel", action: browser.cancelCreatingSpace)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .opacity(0.7)
                .padding(.vertical, 6)
        }
        .padding(.top, 12)
        .onAppear { isNameFocused = true }
        .onExitCommand(perform: browser.cancelCreatingSpace)
        .animation(.snappy(duration: 0.2), value: isThemePickerExpanded)
    }

    /// A fanned stack of cards standing in for Arc's illustration, the middle one showing the icon.
    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                card.rotationEffect(.degrees(-14)).offset(x: -18, y: 4)
                card.rotationEffect(.degrees(14)).offset(x: 18, y: 4)
                card.overlay {
                    if draft.icon == nil {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.swatch(draft.theme))
                    } else {
                        SpaceIcon(space: draft, size: 20)
                    }
                }
            }
            .frame(height: 64)
            Text("Create a Space")
                .font(.system(size: 17, weight: .bold))
            Text("Separate your tabs for life, work, projects, and more.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .opacity(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.white)
            .frame(width: 40, height: 54)
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }

    private var nameField: some View {
        HStack(spacing: 8) {
            Button { browser.beginEditingIcon(of: draft) } label: {
                Group {
                    if draft.icon == nil {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .opacity(0.6)
                    } else {
                        SpaceIcon(space: draft, size: 12)
                    }
                }
                .frame(width: 24, height: 24)
                .overlay {
                    if draft.icon == nil {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.sidebarText.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose Icon")
            .accessibilityLabel("Choose Icon")
            .popover(isPresented: isIconPickerPresented, arrowEdge: .bottom) {
                SpaceIconPicker(space: draft)
                    .environment(browser)
                    .presentationBackground(.thickMaterial)
            }
            TextField("Space name…", text: $draft.name)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isNameFocused)
                .onSubmit(create)
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(Theme.activeTabFill)
        )
    }

    private var themeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { isThemePickerExpanded.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 12))
                        .frame(width: 24)
                        .opacity(0.7)
                    Text("Choose a Theme")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Circle()
                        .fill(Theme.swatch(draft.theme))
                        .frame(width: 12, height: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isThemePickerExpanded {
                HStack(spacing: 0) {
                    ForEach(SpaceTheme.allCases, id: \.self) { theme in
                        ThemeSwatch(theme: theme, isSelected: theme == draft.theme) {
                            browser.setTheme(theme, for: draft)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(Theme.pillFill)
        )
    }

    private var isIconPickerPresented: Binding<Bool> {
        Binding(
            get: { browser.editingIconSpaceID == draft.id },
            set: { if !$0 { browser.endEditingIcon() } }
        )
    }

    private func create() {
        browser.commitSpaceDraft()
    }
}

private struct ThemeSwatch: View {
    let theme: SpaceTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Theme.swatch(theme))
                .frame(width: 20, height: 20)
                .padding(3)
                .overlay(Circle().strokeBorder(Theme.sidebarText.opacity(isSelected ? 0.6 : 0), lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(theme.displayName)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
