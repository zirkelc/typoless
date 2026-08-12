import AppKit
import SwiftUI

/**
 The deny-list, and the settings an app answers differently from the rest.

 Both are keyed by bundle identifier, which is stable across renames and
 updates in a way a path or a display name is not.
 */
struct AppSettingsView: View {
    @Bindable var preferences: Preferences

    @State private var selection: String?

    var body: some View {
        Form {
            Section("Never correct in these apps") {
                List(selection: $selection) {
                    ForEach(deniedApps, id: \.bundleID) { app in
                        AppRow(app: app)
                    }
                }
                .frame(minHeight: 140)

                HStack {
                    Button("Add…", action: addApp)
                    Button("Remove", action: removeSelected)
                        .disabled(selection == nil)
                    Spacer()
                    Button("Reset to Defaults", action: resetDenyList)
                }
            }

            Section("Full stops, per app") {
                if overriddenApps.isEmpty {
                    Text("""
                    Every app follows the global setting. Add one here to have \
                    it answer differently, which is worth doing for a chat app \
                    when the global answer suits your email.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                ForEach(overriddenApps, id: \.bundleID) { app in
                    Toggle(isOn: overrideBinding(for: app.bundleID)) {
                        AppRow(app: app)
                    }
                }

                HStack {
                    Button("Add App…", action: addOverride)
                    Spacer()
                    if !overriddenApps.isEmpty {
                        Button("Remove All") { preferences.appOverrides = [:] }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
        preferences.appOverrides[bundleID] = AppOverride(
            sentenceFinalPunctuation: !preferences.addsSentenceFinalPunctuation
        )
    }

    private func removeSelected() {
        guard let selection else { return }
        preferences.deniedBundleIDs.remove(selection)
        self.selection = nil
    }

    private func resetDenyList() {
        preferences.deniedBundleIDs = TextTargetResolver.defaultDeniedBundleIDs
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
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(app.name)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
