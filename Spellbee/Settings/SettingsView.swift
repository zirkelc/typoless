import SwiftUI

/**
 The look shared by every settings page.

 Labels right-aligned in a narrow left column, controls left-aligned beside
 them, and a hairline between blocks that belong to different ideas. This is the
 layout a Mac settings window has had for twenty years, and the reason to follow
 it is that people can already read it.
 */
struct SettingsPage<Content: View>: View {
    /**
     How wide the labels and controls are, before the window's own margins.

     Fixed rather than filling the window, so the block sits in the middle with
     even space on either side. Letting the form stretch pushes every label to
     the far left and leaves a ragged gap on the right, which is what a settings
     window is not supposed to look like.
     */
    var contentWidth: CGFloat = 520

    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.columns)
        .frame(width: contentWidth)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/**
 A row of one or more controls under a right-aligned label.

 Several checkboxes usually belong to one idea, and repeating a label for each
 of them, or leaving them unlabelled, both read worse than naming the idea once.
 */
struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        LabeledContent(label) {
            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
    }
}

/** An explanation of the control above it, indented to sit under its text. */
struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 20)
            .padding(.bottom, 2)
    }
}

struct GeneralSettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        SettingsPage {
            SettingsRow(label: "Startup:") {
                Toggle("Open Spellbee at login", isOn: launchAtLogin)
            }

            Divider().padding(.vertical, 10)

            SettingsRow(label: "Triggers:") {
                HStack(spacing: 8) {
                    Toggle("Double-tap", isOn: $preferences.isDoubleTapEnabled)

                    Picker("", selection: $preferences.doubleTapModifier) {
                        ForEach(TapModifier.allCases, id: \.self) { modifier in
                            Text(modifier.displayName).tag(modifier)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!preferences.isDoubleTapEnabled)
                }

                SettingsNote(
                    preferences.doubleTapModifier.caution
                        ?? "Tap \(preferences.doubleTapModifier.symbol) twice, quickly. No other key or click in between."
                )

                Toggle("Keyboard shortcut", isOn: $preferences.isHotKeyEnabled)
                ShortcutRecorder(shortcut: $preferences.hotKey)
                    .disabled(!preferences.isHotKeyEnabled)
                    .padding(.leading, 20)
            }

            Divider().padding(.vertical, 10)

            SettingsRow(label: "Stopping:") {
                /**
                 Shown as a key rather than named in a sentence, so it reads the
                 same way as the shortcut above it. Not a recorder: Escape is
                 fixed, because it is claimed only while a correction runs and
                 anything else would have to be taken from the app underneath
                 for the life of the session.
                 */
                Text("Escape")
                    .frame(minWidth: 110)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlColor), in: RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(nsColor: .separatorColor))
                    }

                SettingsNote("Press Escape while a correction is running and nothing is written.")
            }

            Divider().padding(.vertical, 10)

            SettingsRow(label: "Safety:") {
                Toggle("Only fix, never rewrite", isOn: $preferences.isGuardrailEnabled)
                SettingsNote(preferences.isGuardrailEnabled
                    ? "Every change is checked first. Anything that is not spelling, punctuation, capitalisation or spacing is discarded."
                    : "Off: whatever the model returns is applied, including rewritten or translated text. Revert Last Fix is the only way back.")
            }

        }
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

struct PrivacySettingsView: View {
    var body: some View {
        SettingsPage {
            SettingsRow(label: "On this Mac:") {
                Label("Nothing leaves your Mac", systemImage: "lock.fill")
                    .font(.headline)
                SettingsNote("""
                Corrections run on a model on this machine. No text is uploaded, and \
                nothing is sent anywhere for any reason.
                """)
            }

            Divider().padding(.vertical, 10)

            SettingsRow(label: "Logging:") {
                Text("""
                Spellbee writes diagnostic messages to the system log: which app a \
                field was in, how many characters it held, and how many changes were \
                made. The text itself is never among them.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider().padding(.vertical, 10)

            SettingsRow(label: "Never read:") {
                Text("Password fields, and every app in the list under Apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview("General") {
    GeneralSettingsView(preferences: Preferences()).frame(width: 560)
}

