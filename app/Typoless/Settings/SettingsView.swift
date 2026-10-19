import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var preferences: Preferences
    /** Nil in a build without an update feed, which hides the update switch. */
    var updates: UpdateController?

    var body: some View {
        SettingsSurface {
            SettingsSection("App") {
                SettingsLine(
                    "Open at login",
                    note: preferences.launchAtLogin.note
                ) {
                    if preferences.launchAtLogin == .needsApproval {
                        Button("Open Login Items…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }

                    SettingsSwitch(isOn: launchAtLogin)
                }

                if let updates {
                    /** The button that checks now is in About, beside the version it reports on. */
                    SettingsLine("Automatically check for updates") {
                        SettingsSwitch(
                            isOn: Binding(
                                get: { updates.checksAutomatically },
                                set: { updates.setChecksAutomatically($0) }
                            )
                        )
                    }
                }
            }

            SettingsSection("Triggers") {
                SettingsLine(
                    "Double-tap",
                    note: preferences.doubleTapModifier.caution
                        ?? "Tap \(preferences.doubleTapModifier.symbol) twice, quickly, with no other key or click in between."
                ) {
                    Picker("", selection: $preferences.doubleTapModifier) {
                        ForEach(TapModifier.allCases, id: \.self) { modifier in
                            Text(modifier.displayName).tag(modifier)
                        }
                    }
                    .labelsHidden()
                    .disabled(!preferences.isDoubleTapEnabled)

                    SettingsSwitch(isOn: $preferences.isDoubleTapEnabled)
                }

                SettingsLine(
                    "Keyboard shortcut",
                    note: "Press \(preferences.hotKey.displayName)."
                ) {
                    ShortcutRecorder(shortcut: $preferences.hotKey)
                        .disabled(!preferences.isHotKeyEnabled)

                    SettingsSwitch(isOn: $preferences.isHotKeyEnabled)
                }
            }

            SettingsSection("Stopping") {
                SettingsLine(
                    "Cancel key",
                    note: "Press \(preferences.cancelKey.displayName) to cancel a running correction. Claimed only while a correction is running, so a bare key is safe here."
                ) {
                    ShortcutRecorder(
                        shortcut: $preferences.cancelKey,
                        allowsUnmodifiedKeys: true,
                        fallback: .cancel
                    )
                }
            }
        }
    }

    /**
     "Waiting for approval" shows as on, since the user did turn it on and the
     note beside it says what is still missing.
     */
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { preferences.launchAtLogin == .on || preferences.launchAtLogin == .needsApproval },
            set: { preferences.setLaunchesAtLogin($0) }
        )
    }
}

#Preview("General") {
    GeneralSettingsView(preferences: Preferences())
}
