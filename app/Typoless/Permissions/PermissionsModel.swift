@preconcurrency import ApplicationServices
import AppKit
import FoundationModels
import Observation

/**
 Tracks the two gates the app needs before it can do anything useful.

 Neither can be granted programmatically, so the only honest thing the UI can do
 is show live status, deep-link into the right Settings pane, and notice the
 moment the user comes back having flipped the switch.
 */
@MainActor
@Observable
final class PermissionsModel {
    /** Whether this process may read and write text in other applications. */
    private(set) var isAccessibilityTrusted: Bool

    /** Whether the on-device model is usable, and if not, why. */
    private(set) var modelAvailability: SystemLanguageModel.Availability

    /**
     Whether the user has asked for accessibility and has not come back with it.

     The grant happens in another application, and this app cannot know how far
     the user got in it. What it can say is that the question is open, which is
     enough to keep a spinner turning beside the row and to offer the way back
     to the pane instead of asking again.
     */
    private(set) var isAwaitingAccessibility = false

    /** Called whenever a gate opens or closes, including outside any UI. */
    @ObservationIgnored
    var onChange: (() -> Void)?

    private var pollTask: Task<Void, Never>?

    /** Where the one thing this remembers between launches is kept. */
    @ObservationIgnored private let defaults = UserDefaults.standard

    /**
     Other copies of this app on this Mac, which is the usual reason a switch
     that is visibly on does not apply to the app that is asking.

     Two copies of one app appear in System Settings as two rows with the same
     name, since that list names an app by its file rather than by what is
     inside it, and only the copy that was allowed can read text. What the user
     sees is an app that ignores a permission they can see is granted.
     */
    private(set) var otherCopies: [URL] = []

    /**
     Written once during init and read once during deinit, which runs outside
     the main actor. Never mutated after init, so the unchecked access is safe.
     */
    @ObservationIgnored
    private nonisolated(unsafe) var trustObserver: (any NSObjectProtocol)?

    var isReady: Bool {
        isAccessibilityTrusted && modelAvailability == .available
    }

    init() {
        isAccessibilityTrusted = false
        modelAvailability = SystemLanguageModel.default.availability
        isAccessibilityTrusted = isTrustedNow

        Log.permissions.info(
            "Launched with accessibility trusted: \(self.isAccessibilityTrusted, privacy: .public), model: \(String(describing: self.modelAvailability), privacy: .public)"
        )

        /**
         The system posts this when any application's accessibility trust
         changes, which turns most grants into an instant update rather than
         one that waits for the next poll.
         */
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let trustObserver {
            DistributedNotificationCenter.default().removeObserver(trustObserver)
        }
    }

    /**
     Asks for accessibility, which is the only thing here the user pressed a
     button for.

     The trust check has a prompt option, which registers the app with the
     system and offers it to the user. It used to run at launch, where it put a
     system dialog in front of somebody who had opened the app for the first
     time and had not yet been told what it was for. Setup asks first now, and
     this runs when they answer.

     Both the dialog and the Settings pane are the same request, and the pane is
     opened whatever the dialog decides to do: whether anything is shown at all
     is the system's call, it stays silent for an app it has already offered,
     and it stays silent for a sandboxed app, where the request is dropped
     without a trace and the app never reaches the list at all. That is why this
     app is unsandboxed.
     */
    func requestAccessibility() {
        if isTrustedNow {
            refresh()
            return
        }

        isAwaitingAccessibility = true

        /**
         The first press asks the system, which registers the app so that it has
         a row to switch on, and puts up a dialog whose own button opens the
         right pane. Opening that pane ourselves as well put two windows on
         screen for one press, each saying the same thing.

         Every press after that goes straight to the pane, because the system
         shows its dialog for an app it has already offered at most once, and a
         button that may or may not do something visible is worse than one that
         always does the same thing.
         */
        let key = DefaultsKey.hasAskedForAccessibility
        guard defaults.bool(forKey: key) else {
            defaults.set(true, forKey: key)

            let option = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
            _ = AXIsProcessTrustedWithOptions([option: kCFBooleanTrue as Any] as CFDictionary)

            return
        }

        openAccessibilitySettings()
    }

    /**
     What to say under the accessibility row, or nothing when there is nothing
     useful to say.

     Only while the permission is refused and only while a second copy exists,
     because a path is worth reading exactly then: with one copy the row in
     System Settings is already unambiguous, and a line every user reads past is
     worse than no line.
     */
    var accessibilityNote: String? {
        guard !isAccessibilityTrusted, let other = otherCopies.first else { return nil }

        /** The name the user sees in the list, which a debug build tags as its own. */
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? "Typoless"
        let elsewhere = otherCopies.count > 1
            ? "\(Self.shortPath(other)), and \(otherCopies.count - 1) more"
            : Self.shortPath(other)

        return """
        Another copy of \(name) is at \(elsewhere). Each copy has its own switch, \
        so allow this one, at \(Self.shortPath(Bundle.main.bundleURL)).
        """
    }

    /** Written the way the user sees it in the Finder, with the home folder as a tilde. */
    private static func shortPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    /**
     Asked of LaunchServices when a permissions UI appears, rather than on every
     poll: it answers from a database, and copies of an app do not come and go
     by the second.
     */
    private func findOtherCopies() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }

        let here = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let copies = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: identifier)
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            .filter { $0 != here }
            /**
             Only copies that are still there. LaunchServices remembers every
             place it has ever seen this app, which on a machine that has
             installed it once includes the disk image it was dragged out of and
             whatever was thrown away afterwards. Warning about those would be
             warning about nothing.
             */
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        if copies != otherCopies {
            otherCopies = copies

            if let first = copies.first {
                Log.permissions.info(
                    "Another copy of this app is installed at \(first.path, privacy: .public), of \(copies.count, privacy: .public) in all"
                )
            }
        }
    }

    /**
     Whether this app may read and write text in other applications.

     In a debug build a default can hold the answer down at false. The setup
     window and the helper that goes with it are only ever seen by somebody who
     has not granted the permission yet, and a developer has granted it: the
     alternative is taking the permission away to look at the window, which
     takes the whole app down with it and needs a password to put back.
     */
    private var isTrustedNow: Bool {
        #if DEBUG
        if defaults.bool(forKey: DefaultsKey.pretendAccessibilityMissing) { return false }
        #endif

        return AXIsProcessTrusted()
    }

    func refresh() {
        var didChange = false

        let trusted = isTrustedNow
        if trusted != isAccessibilityTrusted {
            isAccessibilityTrusted = trusted
            didChange = true
            Log.permissions.info("Accessibility trust changed to \(trusted, privacy: .public)")
        }

        if trusted, isAwaitingAccessibility {
            isAwaitingAccessibility = false
        }

        let availability = SystemLanguageModel.default.availability
        if availability != modelAvailability {
            modelAvailability = availability
            didChange = true
            Log.permissions.info("Model availability changed to \(String(describing: availability), privacy: .public)")
        }

        if didChange {
            onChange?()
        }
    }

    /**
     Polls while a permissions UI is on screen. The distributed notification
     covers accessibility, but model availability has no equivalent signal, and
     a user who enables Apple Intelligence mid-onboarding should still see the
     row turn green without relaunching.
     */
    func startMonitoring() {
        guard pollTask == nil else { return }

        findOtherCopies()

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    /**
     Opens the list this app has to appear in.

     The pane is named after the extension that draws it rather than after the
     preference pane it replaced. Both names are accepted, and they do not go to
     the same place: the older one now stops at Privacy and Security, one level
     above the list, which leaves the user looking at twenty categories with no
     reason to think Accessibility is the one. The anchor is only honoured by
     the name that is current.
     */
    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
    }

    func openAppleIntelligenceSettings() {
        open("x-apple.systempreferences:com.apple.Siri-Settings.extension")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

extension SystemLanguageModel.Availability {
    /** User-facing explanation of why the model cannot be used right now. */
    var explanation: String {
        switch self {
        case .available:
            return "The on-device model is ready."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings."
        case .unavailable(.modelNotReady):
            return "macOS is still downloading the model. This finishes on its own."
        case .unavailable(.deviceNotEligible):
            return "This Mac does not support Apple Intelligence."
        case .unavailable:
            return "The on-device model is unavailable."
        }
    }

    /** Whether the user can do anything about the current state. */
    var isActionable: Bool {
        switch self {
        case .available, .unavailable(.deviceNotEligible), .unavailable(.modelNotReady):
            return false
        default:
            return true
        }
    }
}
