import AppKit

/**
 An app named by bundle identifier, resolved to something a person recognises.

 The app need not be installed: the exclusion list is seeded with defaults, and
 a machine without Xcode should still show the Xcode entry rather than dropping
 it, so the identifier stands in for the name when nothing can be found.
 */
struct InstalledApp {
    /**
     Resolved once per identifier per session.

     Each construction makes three LaunchServices and FileManager calls, and it
     was built inside a SwiftUI computed property, so ten excluded apps meant
     thirty round trips on every redraw of the list, and again for every row of
     the history window. The mapping does not change while the app is running.
     */
    @MainActor private static var cache: [String: InstalledApp] = [:]

    @MainActor
    static func named(_ bundleID: String) -> InstalledApp {
        if let known = cache[bundleID] { return known }

        let resolved = InstalledApp(bundleID: bundleID)
        cache[bundleID] = resolved

        return resolved
    }

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
