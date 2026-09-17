import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        SettingsSurface {
            SettingsSection("App") {
                SettingsLine(
                    "Open at login",
                    note: preferences.launchAtLogin == .needsApproval
                        ? "Waiting for your approval under Login Items in System Settings."
                        : nil
                ) {
                    if preferences.launchAtLogin == .needsApproval {
                        Button("Open Login Items…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }

                    SettingsSwitch(isOn: launchAtLogin)
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
            get: { preferences.launchAtLogin != .off },
            set: { preferences.setLaunchesAtLogin($0) }
        )
    }
}

struct PrivacySettingsView: View {
    var body: some View {
        SettingsSurface {
            SettingsSection("On this Mac") {
                SettingsText(
                    "Nothing leaves your Mac",
                    text: "Corrections run on a local model on this machine. No text is uploaded and nothing is sent anywhere."
                )
            }

            SettingsSection("Never read") {
                SettingsText(text: """
                Password fields are always ignored. Every app excluded under Apps is \
                always ignored, and if you have named apps to correct in, every other \
                app as well.
                """)
            }
        }
    }
}

#Preview("General") {
    GeneralSettingsView(preferences: Preferences())
}
