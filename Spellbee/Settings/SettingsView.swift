import SwiftUI

/** Everything the user can change, grouped by what they are trying to achieve. */
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }

            LanguageSettingsView(preferences: model.preferences)
                .tabItem { Label("Languages", systemImage: "globe") }

            CorrectionSettingsView(preferences: model.preferences)
                .tabItem { Label("Corrections", systemImage: "checkmark.circle") }

            AppSettingsView(preferences: model.preferences)
                .tabItem { Label("Apps", systemImage: "app.badge") }

            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "lock") }
        }
        .frame(width: 540, height: 460)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var preferences: Preferences

    init(model: AppModel) {
        preferences = model.preferences
    }

    var body: some View {
        Form {
            Section {
                Toggle("Open Spellbee at login", isOn: launchAtLogin)
            }

            Section("Triggers") {
                Toggle("Double-tap ⌘", isOn: $preferences.isDoubleTapEnabled)
                Text("Tap Command twice, quickly. Nothing else may happen in between.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Keyboard shortcut", isOn: $preferences.isHotKeyEnabled)
                ShortcutRecorder(shortcut: $preferences.hotKey)
                    .disabled(!preferences.isHotKeyEnabled)
            }

            Section {
                LabeledContent("While correcting") {
                    Text("Press Escape to stop. Nothing is written if you do.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /**
     Written straight through to the system rather than mirrored, since the user
     can turn it off in System Settings without telling us.
     */
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { preferences.launchesAtLogin },
            set: { preferences.launchesAtLogin = $0 }
        )
    }
}

private struct LanguageSettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Languages") {
                ForEach(CorrectionLanguage.allCases, id: \.self) { language in
                    Toggle(language.displayName, isOn: binding(for: language))
                }
            }

            Section {
                Text("""
                The language of each paragraph is detected, and only the \
                languages enabled here are considered. Turning one off is worth \
                doing if your writing is never mistaken for it.

                At least one language stays on.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for language: CorrectionLanguage) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledLanguages.contains(language) },
            set: { isOn in
                var languages = preferences.enabledLanguages
                if isOn { languages.insert(language) } else { languages.remove(language) }
                preferences.enabledLanguages = languages
            }
        )
    }
}

private struct CorrectionSettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Only fix, never rewrite", isOn: $preferences.isGuardrailEnabled)
                Text(preferences.isGuardrailEnabled
                    ? "Every change is checked before it is applied. Anything that is not spelling, punctuation, capitalisation or spacing is discarded."
                    : "Off: whatever the model returns is applied, including rewritten or translated text. Revert Last Fix is the only way back.")
                    .font(.caption)
                    .foregroundStyle(preferences.isGuardrailEnabled ? .secondary : .primary)
            }

            Section("What to fix") {
                ForEach(EditKind.allCases, id: \.self) { kind in
                    Toggle(kind.displayName, isOn: binding(for: kind))
                }
            }
            .disabled(!preferences.isGuardrailEnabled)

            Section("Sentence endings") {
                Toggle(
                    "Add a full stop to a finished sentence",
                    isOn: $preferences.addsSentenceFinalPunctuation
                )
                Text("""
                A message that stops without a closing mark is not a mistake, \
                and in a chat a full stop changes the tone. This is the single \
                largest source of changes you did not ask for, so it can be \
                turned off here and per app.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .disabled(!preferences.isGuardrailEnabled)
        }
        .formStyle(.grouped)
    }

    private func binding(for kind: EditKind) -> Binding<Bool> {
        Binding(
            get: { preferences.allowedKinds.contains(kind) },
            set: { isOn in
                var kinds = preferences.allowedKinds
                if isOn { kinds.insert(kind) } else { kinds.remove(kind) }
                preferences.allowedKinds = kinds
            }
        )
    }
}

private struct PrivacySettingsView: View {
    var body: some View {
        Form {
            Section {
                Label("Nothing leaves your Mac", systemImage: "lock.fill")
                    .font(.headline)

                Text("""
                Corrections run on a model on this machine. No text is uploaded, \
                and nothing is sent anywhere for any reason.

                Spellbee writes diagnostic messages to the system log: which app \
                a field was in, how many characters it held, and how many changes \
                were made. The text itself is never among them.

                Passwords are skipped. So is any app in the deny-list.
                """)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView(model: AppModel())
}
