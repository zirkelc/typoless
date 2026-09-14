import AppKit
import SwiftUI

/**
 Where Spellbee is allowed to correct.

 Two lists answering two different questions, both always on screen. The
 exclusions are the ones that matter, so they come first and they always apply:
 nothing added to the list below can put a terminal or a password manager back.
 The inclusions are optional and only narrow what is left.

 Keyed by bundle identifier, which is stable across renames and updates in a way
 a path or a display name is not.
 */
struct AppSettingsView: View {
    @Bindable var preferences: Preferences

    /** One per table, since a row stays picked while the other table is used. */
    @State private var excludedSelection: String?
    @State private var includedSelection: String?

    var body: some View {
        SettingsSurface {
            AppList(
                title: "Never correct in",
                bundleIDs: preferences.deniedBundleIDs,
                selection: $excludedSelection,
                emptyMessage: "No exceptions. Spellbee corrects everywhere.",
                onAdd: { preferences.deniedBundleIDs.insert($0) },
                onRemove: { preferences.deniedBundleIDs.remove($0) },
                onReset: { preferences.deniedBundleIDs = AppPolicy.defaultDenied }
            )

            SettingsFootnote("""
            Terminals, editors and password managers, where a "text field" is \
            usually code, a command, or a secret. Always applies.
            """)

            Divider().padding(.vertical, 6)

            AppList(
                title: "Only correct in",
                trailing: "Optional",
                bundleIDs: preferences.allowedBundleIDs,
                selection: $includedSelection,
                emptyMessage: "No apps. Spellbee corrects everywhere it is allowed.",
                onAdd: { preferences.allowedBundleIDs.insert($0) },
                onRemove: { preferences.allowedBundleIDs.remove($0) }
            )

            SettingsFootnote("""
            Leave this empty to correct everywhere. Name even one app and \
            Spellbee works there and nowhere else, minus anything excluded above.
            """)

        }
    }
}

/**
 One editable list of apps.

 Both tables behave identically apart from their wording and which set they
 write to, and the second one arrived by having the first one's behaviour
 described twice. Reset is offered only where there is something to go back to.
 */
private struct AppList: View {
    let title: String
    var trailing: String?
    let bundleIDs: Set<String>
    @Binding var selection: String?
    let emptyMessage: String
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void
    var onReset: (() -> Void)?

    private var apps: [InstalledApp] {
        bundleIDs.map(InstalledApp.named).sorted { $0.name < $1.name }
    }

    var body: some View {
        Table {
            TableHeader(title, trailing: trailing)

            ForEach(apps, id: \.bundleID) { app in
                Divider()

                AppRow(app: app, isSelected: selection == app.bundleID)
                    .onTapGesture { selection = app.bundleID }
            }

            if apps.isEmpty {
                Divider()

                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        HStack(spacing: 8) {
            Button("Add App…") { add() }
            Button("Remove") { remove() }
                .disabled(selection == nil)

            if let onReset {
                Spacer()
                Button("Reset") {
                    onReset()
                    selection = nil
                }
            }
        }
    }

    private func add() {
        guard let bundleID = chooseApplication() else { return }

        onAdd(bundleID)
        selection = bundleID
    }

    private func remove() {
        guard let selection else { return }

        onRemove(selection)
        self.selection = nil
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

#Preview {
    AppSettingsView(preferences: Preferences())
}
