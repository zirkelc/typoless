import AppKit
import SwiftUI

/**
 The deny-list, and the settings an app answers differently from the rest.

 Both are keyed by bundle identifier, which is stable across renames and updates
 in a way a path or a display name is not.
 */
struct AppSettingsView: View {
    @Bindable var preferences: Preferences

    @State private var deniedSelection: String?
    @State private var overrideSelection: String?

    var body: some View {
        SettingsPage {
            SettingsRow(label: "Never correct in:") {
                List(selection: $deniedSelection) {
                    ForEach(deniedApps, id: \.bundleID) { app in
                        AppRow(app: app).tag(app.bundleID)
                    }
                }
                .frame(height: 150)
                .border(Color(nsColor: .separatorColor))

                HStack(spacing: 8) {
                    Button("Add…") { addApp() }
                    Button("Remove") { removeDenied() }
                        .disabled(deniedSelection == nil)
                    Spacer()
                    Button("Reset") {
                        preferences.deniedBundleIDs = TextTargetResolver.defaultDeniedBundleIDs
                    }
                }

                SettingsNote("Terminals, editors and password managers, where a \"text field\" is usually code, a command, or a secret.")
            }

            Divider().padding(.vertical, 10)

            SettingsRow(label: "Full stops:") {
                Text(preferences.addsSentenceFinalPunctuation
                    ? "Everywhere else, a finished sentence gets a full stop."
                    : "Everywhere else, no full stop is added.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                List(selection: $overrideSelection) {
                    ForEach(overriddenApps, id: \.bundleID) { app in
                        Toggle(isOn: overrideBinding(for: app.bundleID)) {
                            AppRow(app: app)
                        }
                        .tag(app.bundleID)
                    }
                }
                .frame(height: 110)
                .border(Color(nsColor: .separatorColor))
                .overlay {
                    if overriddenApps.isEmpty {
                        Text("Every app follows the setting above.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 8) {
                    Button("Add App…") { addOverride() }
                    Button("Remove") { removeOverride() }
                        .disabled(overrideSelection == nil)
                }

                SettingsNote("Worth setting for a chat app when the answer above suits your email, or the other way round.")
            }
        }
    }

    private var deniedApps: [InstalledApp] {
        preferences.deniedBundleIDs.map(InstalledApp.init).sorted { $0.name < $1.name }
    }

    private var overriddenApps: [InstalledApp] {
        preferences.appOverrides.keys.map(InstalledApp.init).sorted { $0.name < $1.name }
    }

    private func overrideBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: {
                preferences.appOverrides[bundleID]?.sentenceFinalPunctuation
                    ?? preferences.addsSentenceFinalPunctuation
            },
            set: { preferences.appOverrides[bundleID] = AppOverride(sentenceFinalPunctuation: $0) }
        )
    }

    private func addApp() {
        guard let bundleID = chooseApplication() else { return }
        preferences.deniedBundleIDs.insert(bundleID)
    }

    private func addOverride() {
        guard let bundleID = chooseApplication() else { return }

        /** Added to differ, so it starts as the opposite of the global answer. */
        preferences.appOverrides[bundleID] = AppOverride(
            sentenceFinalPunctuation: !preferences.addsSentenceFinalPunctuation
        )
    }

    private func removeDenied() {
        guard let deniedSelection else { return }
        preferences.deniedBundleIDs.remove(deniedSelection)
        self.deniedSelection = nil
    }

    private func removeOverride() {
        guard let overrideSelection else { return }
        preferences.appOverrides[overrideSelection] = nil
        self.overrideSelection = nil
    }

    /** Nil when the user cancels, or picks something with no bundle identifier. */
    private func chooseApplication() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        return Bundle(url: url)?.bundleIdentifier
    }
}

private struct AppRow: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 16, height: 16)

            Text(app.name)
            Text(app.bundleID)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/**
 An app named by bundle identifier, resolved to something a person recognises.

 A denied app need not be installed: the list is seeded with defaults, and a
 machine without Xcode should still show the Xcode entry rather than dropping
 it, so the identifier stands in for the name when nothing can be found.
 */
private struct InstalledApp {
    let bundleID: String
    let name: String
    let icon: NSImage

    init(bundleID: String) {
        self.bundleID = bundleID

        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)

        name = url.flatMap { FileManager.default.displayName(atPath: $0.path) }
            ?? bundleID.components(separatedBy: ".").last
            ?? bundleID

        icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil)
            ?? NSImage()
    }
}

#Preview {
    AppSettingsView(preferences: Preferences()).frame(width: 620)
}
