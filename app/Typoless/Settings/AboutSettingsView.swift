import AppKit
import SwiftUI

/**
 What this app is, where it came from, and the way back to its first run.

 This replaces two things. One was a Privacy tab holding two paragraphs and no
 setting, which is a page nobody opens twice. The other was the system About
 panel, which shows the icon, the name and the version and then stops: there is
 nowhere in it to put a link, and nowhere to put the button that opens setup
 again.

 That button is the reason this page earns a tab. Setup can be reopened from
 the menu bar only while a permission is still missing, which is right, since
 after that it is a tour rather than a repair. A tour still has to be
 reachable, and this is where somebody looks for it.
 */
struct AboutSettingsView: View {
    let model: AppModel

    private static let website = URL(string: "https://typoless.app")!
    private static let privacy = URL(string: "https://typoless.app/privacy")!
    private static let source = URL(string: "https://github.com/\(IssueTracker.repository)")!

    var body: some View {
        SettingsSurface {
            SettingsSection {
                identity
            }

            SettingsSection("Links") {
                LinkLine(title: "Website", url: Self.website)
                LinkLine(title: "Privacy", url: Self.privacy)
                LinkLine(title: "Source", url: Self.source)
                licences
            }

            SettingsSection("Setup") {
                SettingsLine(
                    "Setup tour",
                    note: "The pages from the first launch: what the keys do, which languages Typoless corrects, and how to undo a correction."
                ) {
                    Button("Show") { model.showOnboarding() }
                }
            }

            SettingsSection("Privacy") {
                SettingsText(
                    "Nothing leaves your Mac",
                    text: "Corrections run on a model on this machine. Your text never leaves it, and there is no account."
                )
            }
        }
    }

    /** The icon, the name and the version, with the one button that acts on them. */
    private var identity: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(Self.appName)
                    .font(.headline)

                Text(Self.version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            /**
             Beside the version rather than on the General page, which is where
             it was. The question "am I up to date" is asked of the number, so
             the answer belongs against the number. Whether to look on its own
             is a preference and stays with the other preferences.
             */
            if let updates = model.updates {
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
            }
        }
        .settingsRow()
    }

    /**
     The licence notices for every package the app ships.

     Not decoration: the MIT, Apache and BSD licences all require their text to
     travel with the software, which it does, as a file in the bundle. A
     missing file is a packaging mistake, and the row says so rather than
     quietly shipping without the notices the licences ask for.
     */
    @ViewBuilder private var licences: some View {
        if let notices = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
            SettingsLine("Open-source licences") {
                Button("Open") { NSWorkspace.shared.open(notices) }
            }
        } else {
            SettingsText(
                "Open-source licences",
                text: "The licence notices are missing from this build."
            )
            .foregroundStyle(.red)
            .onAppear { Log.app.error("Acknowledgements.txt is missing from the bundle") }
        }
    }

    private static var appName: String {
        let info = Bundle.main.infoDictionary

        return info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? "Typoless"
    }

    /** Both numbers, since a beta is identified by its build as often as its name. */
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        return "Version \(short) (\(build))"
    }
}

/**
 One address, named on the left and readable on the right.

 The address itself rather than a "Visit" button, so that it is clear where the
 click goes before it is clicked, and so the same line can be read out or
 typed in by hand.
 */
private struct LinkLine: View {
    let title: String
    let url: URL

    var body: some View {
        SettingsLine(title) {
            Link(destination: url) {
                HStack(spacing: 3) {
                    Text(shortened)

                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                }
            }
            .accessibilityLabel("\(title), \(shortened)")
        }
    }
}

private extension LinkLine {
    /** As it is written on paper: no scheme, and no trailing slash. */
    var shortened: String {
        guard let host = url.host() else { return url.absoluteString }

        let path = url.path()

        return path.isEmpty || path == "/" ? host : host + path
    }
}
