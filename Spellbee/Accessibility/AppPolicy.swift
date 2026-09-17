import Foundation

/**
 Which apps may be corrected in.

 Kept apart from the resolver, and free of AppKit, because this is the rule that
 decides whether Spellbee reads someone's text at all. That deserves to be a
 plain function of two sets, checkable on its own.

 Two lists that answer two different questions, rather than one list read two
 ways. Exclusions always apply: a terminal or a password manager stays out
 however the rest is configured, so no amount of editing the second list can
 quietly put it back. Inclusions are optional and narrow what is left: empty
 means everywhere, and naming even one app means only the apps named.

 The asymmetry is deliberate. The permissive setting is the one that has to be
 typed out in full, and the protective one is the one that cannot be lost by
 accident.
 */
struct AppPolicy: Sendable {
    /**
     Apps where correcting text is more likely to cause harm than help: shells,
     editors and password managers, where the "text field" is usually code, a
     command, or a secret. Seeds the exclusion list the user can then edit.
     */
    static var defaultDenied: Set<String> { Set(defaultDeniedNames.keys) }

    /**
     The same apps with the names people know them by.

     Needed because most machines have only a few of them installed, and an app
     that is not installed has no name to look up. The list then showed
     `230313mzl4w4u92` where it meant Cursor.
     */
    static let defaultDeniedNames: [String: String] = [
        "com.apple.Terminal": "Terminal",
        "com.googlecode.iterm2": "iTerm2",
        "com.mitchellh.ghostty": "Ghostty",
        "dev.warp.Warp-Stable": "Warp",
        "com.apple.dt.Xcode": "Xcode",
        "com.microsoft.VSCode": "Visual Studio Code",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.jetbrains.intellij": "IntelliJ IDEA",
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
    ]

    var denied: Set<String> = defaultDenied
    var allowed: Set<String> = []

    /** Why an app was passed over, since the two reasons are worth saying differently. */
    enum Decision: Equatable {
        case allowed
        /** Named in the exclusion list. */
        case excluded
        /** Correcting is limited to a list, and this app is not on it. */
        case notIncluded
    }

    /**
     A frontmost app with no bundle identifier cannot be named by either list, so
     it is treated as any other unnamed app: fine while the inclusion list is
     empty, and left out once one exists.
     */
    func decision(for bundleID: String?) -> Decision {
        if let bundleID, denied.contains(bundleID) { return .excluded }

        guard !allowed.isEmpty else { return .allowed }

        guard let bundleID, allowed.contains(bundleID) else { return .notIncluded }

        return .allowed
    }

    func permits(_ bundleID: String?) -> Bool {
        decision(for: bundleID) == .allowed
    }
}
