import AppKit
import SwiftUI

/**
 The apps Spellbee leaves alone.

 Keyed by bundle identifier, which is stable across renames and updates in a way
 a path or a display name is not.

 Per-app answers for sentence endings are still carried by `Preferences` and
 honoured by the engine; only the table for editing them is gone, so anything
 already set keeps working.
 */
struct AppSettingsView: View {
    @Bindable var preferences: Preferences

    @State private var deniedSelection: String?

    var body: some View {
        SettingsSurface {
            Table {
                TableHeader("Never correct in")

                ForEach(deniedApps, id: \.bundleID) { app in
                    Divider()

                    AppRow(app: app, isSelected: deniedSelection == app.bundleID)
                        .onTapGesture { deniedSelection = app.bundleID }
                }
            }

            HStack(spacing: 8) {
                Button("Add App…") { addApp() }
                Button("Remove") { removeDenied() }
                    .disabled(deniedSelection == nil)
                Spacer()
                Button("Reset") {
                    preferences.deniedBundleIDs = TextTargetResolver.defaultDeniedBundleIDs
                    deniedSelection = nil
                }
            }

            SettingsFootnote("""
            Terminals, editors and password managers, where a "text field" is \
            usually code, a command, or a secret.
            """)

        }
    }

    private var deniedApps: [InstalledApp] {
        preferences.deniedBundleIDs.map(InstalledApp.init).sorted { $0.name < $1.name }
    }

    private func addApp() {
        guard let bundleID = chooseApplication() else { return }
        preferences.deniedBundleIDs.insert(bundleID)
        deniedSelection = bundleID
    }

    private func removeDenied() {
        guard let deniedSelection else { return }
        preferences.deniedBundleIDs.remove(deniedSelection)
        self.deniedSelection = nil
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
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 16, height: 16)

            /**
             A fixed column so the identifiers line up down the page. Left to
             size themselves they start at a different place on every row, which
             makes a list of ten look like ten unrelated things.
             */
            Text(app.name)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            /** The identifier is what this is keyed on, so it is worth showing. */
            Text(app.bundleID)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        .contentShape(Rectangle())
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
    AppSettingsView(preferences: Preferences())
}
