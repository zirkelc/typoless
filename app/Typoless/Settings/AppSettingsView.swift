import AppKit
import SwiftUI

/**
 Where Typoless is allowed to correct.

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
                emptyMessage: "No exceptions. Typoless corrects everywhere.",
                onAdd: { preferences.deniedBundleIDs.insert($0) },
                onRemove: { preferences.deniedBundleIDs.remove($0) },
                onReset: { preferences.deniedBundleIDs = AppPolicy.defaultDenied },
                note: "Never correct in these apps, or leave empty to correct everywhere."
            )

            AppList(
                title: "Only correct in",
                trailing: "Optional",
                bundleIDs: preferences.allowedBundleIDs,
                selection: $includedSelection,
                emptyMessage: "No apps. Typoless corrects everywhere it is allowed.",
                onAdd: { preferences.allowedBundleIDs.insert($0) },
                onRemove: { preferences.allowedBundleIDs.remove($0) },
                note: "Only correct in these apps, or leave empty to correct everywhere."
            )
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
    let note: String

    private var apps: [InstalledApp] {
        bundleIDs.map(InstalledApp.named).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        /** The page holds two lists, so each one needs its name. */
        SettingsSection(title, trailing: trailing, footer: note) {
            if apps.isEmpty {
                Text(emptyMessage)
                    .settingsEmptyRow()
            }

            ForEach(apps, id: \.bundleID) { app in
                AppRow(app: app, isSelected: selection == app.bundleID)
                    .onTapGesture { selection = app.bundleID }
            }
        } actions: {
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
                .frame(width: 190, alignment: .leading)

            /** The identifier is what this is keyed on, so it is worth showing. */
            Text(app.bundleID)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .settingsRow()
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        .contentShape(Rectangle())
    }
}

#Preview {
    AppSettingsView(preferences: Preferences())
}
