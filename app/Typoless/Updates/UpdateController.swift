import Foundation
import Observation
import Sparkle

/**
 Checks for new versions, and installs the one the user agrees to.

 There is no store behind this app, so nothing updates it unless it updates
 itself. Without this, shipping a fix means asking every user to go back to a
 website and drag a new copy over the old one, which most of them will never do:
 the version that fixes a bad correction would sit on the server while the
 version making the bad correction stays in the menu bar.

 Sparkle is the standard answer, and it is doing something that deserves the
 caution: downloading code and running it on the user's machine. Two things keep
 that honest, and neither is optional.

 **Every update is signed with a key that is not in this repository.** The
 public half is in the built app, the private half is not in the project at all,
 so the feed can be replaced, the download can be intercepted, and an update
 still cannot be installed. A missing or wrong signature is refused, and with
 no key in the built app Sparkle refuses everything, which is the safe direction
 to fail in.

 **Nothing is installed until the user says so.** Checking is on from the first
 launch, because a check is one request a day carrying the app's name and
 version, and the promise this app makes is about the text you type, not about a
 version number. It never sends the profile of the Mac that Sparkle can attach,
 because the app never offers it. Finding an update installs nothing: the app
 says so in the menu and waits for the button to be pressed, and
 `automaticallyDownloadsUpdates` is deliberately never turned on.

 **The quiet check probes, and the scheduling is ours.** Sparkle's own schedule
 came first, with the gentle reminder API to stop its window arriving in the
 middle of a sentence somebody was writing. That works, but a deferred update is
 a session Sparkle holds open, and while one is open it makes no further checks:
 a mark raised on Sunday still offered Sunday's version on Tuesday, and the user
 had to update twice to catch up. `checkForUpdateInformation` finds an update
 without offering it and leaves nothing open, so the mark is only ever a note
 that something was there when we last looked, and pressing it asks the server
 again.
 */
@MainActor
@Observable
final class UpdateController {
    /**
     Where the list of versions lives.

     Read from the built app rather than written here, so the feed can differ
     between a local build and a release without a code change.
     */
    static var feedURL: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    /** Whether the app was built with everything an update needs. */
    static var isConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String

        return feedURL?.isEmpty == false && key?.isEmpty == false
    }

    /** How long between quiet checks. */
    private static let interval: TimeInterval = 24 * 60 * 60

    /**
     How long a check that is already due waits after launch.

     Launching is when the app has a model to load and permissions to read, and
     a feed request in the middle of that buys nothing: nobody is looking at the
     menu bar in the first seconds either.
     */
    private static let settlingDelay: Duration = .seconds(20)

    @ObservationIgnored private let updater: SPUStandardUpdaterController

    /**
     Held here because Sparkle does not retain its delegate.

     Without this property the channel answer would be given by an object that
     has already gone, which is the same as never giving it: a beta build would
     read the feed and find nothing addressed to it.
     */
    @ObservationIgnored private let delegate = UpdaterDelegate()

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    @ObservationIgnored private let defaults = UserDefaults.standard

    /**
     The version the last check found, or nil where it found nothing. What the
     menu bar reads to decide whether to mark itself.

     A version string rather than the update itself, because this crosses from
     Sparkle's callback to the main actor and a string is the whole of what the
     menu has to say.
     */
    private(set) var availableUpdate: String?

    /**
     Whether the app looks for a new version once a day.

     Ours rather than Sparkle's, because Sparkle's scheduler is off: its own
     setting would be a switch that changed nothing.
     */
    private(set) var checksAutomatically: Bool

    /** When the last quiet check ran, kept so a relaunch does not start the day again. */
    private(set) var lastCheck: Date?

    init() {
        checksAutomatically = defaults.object(forKey: DefaultsKey.checksForUpdates) as? Bool ?? true
        lastCheck = defaults.object(forKey: DefaultsKey.lastUpdateCheck) as? Date

        /**
         Started by hand once the settings are applied, so Sparkle's scheduler
         is off before it could run anything, and so its own question about
         automatic checks is never reached: it asks only where that answer is
         unset, and this sets it on every launch.
         */
        updater = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        updater.updater.automaticallyChecksForUpdates = false
        updater.updater.automaticallyDownloadsUpdates = false
        updater.startUpdater()

        delegate.onResult = { [weak self] version in
            self?.record(version)
        }

        startPolling()
    }

    func setChecksAutomatically(_ isOn: Bool) {
        guard isOn != checksAutomatically else { return }

        checksAutomatically = isOn
        defaults.set(isOn, forKey: DefaultsKey.checksForUpdates)

        guard isOn else {
            pollTask?.cancel()
            pollTask = nil

            /** Nothing is looking any more, so the mark would be about a check that no longer happens. */
            availableUpdate = nil
            return
        }

        startPolling()
    }

    /**
     What the menu item does, and the only path that reports "you are up to
     date".

     A real check every time, because nothing is being held back for it to
     resume: the quiet checks probe and offer nothing, so what opens here is
     always about the version on the server now.
     */
    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }

    /**
     Whether the menu item can do anything right now.

     Sparkle refuses to check while an update is already in flight, and a menu
     item that does nothing when clicked is worse than one that is visibly
     unavailable.
     */
    var canCheckForUpdates: Bool {
        updater.updater.canCheckForUpdates
    }

    /**
     Looks without offering.

     The delegate hears what was found either way, which is what raises the mark
     and what clears it. Skipped while Sparkle has something of its own in
     progress, since a probing check does nothing then and would only move the
     clock on.
     */
    private func check() {
        guard !updater.updater.sessionInProgress else { return }

        lastCheck = Date()
        defaults.set(lastCheck, forKey: DefaultsKey.lastUpdateCheck)

        updater.updater.checkForUpdateInformation()
    }

    /**
     The daily rhythm, kept here rather than by Sparkle.

     Sleeps until the next one is due rather than waking every hour to ask,
     since the answer is a subtraction and the app is running the whole time.
     */
    private func startPolling() {
        pollTask?.cancel()

        guard checksAutomatically, Self.isConfigured else { return }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.delayUntilNextCheck else { return }

                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }

                self?.check()
            }
        }
    }

    private var delayUntilNextCheck: Duration {
        guard let lastCheck else { return Self.settlingDelay }

        let due = lastCheck.addingTimeInterval(Self.interval).timeIntervalSinceNow

        return due <= 0 ? Self.settlingDelay : .seconds(due)
    }

    private func record(_ version: String?) {
        availableUpdate = version

        /**
         The one trace an update leaves before anybody clicks anything. Without
         it, a mark that never appears and a check that found nothing look
         exactly alike from the outside.
         */
        if let version {
            Log.app.info("An update is waiting, version \(version, privacy: .public)")
        }
    }
}

/**
 What this build may be told about, and what it was told.

 One feed carries every release. An entry may name a channel, and Sparkle
 ignores any channel the build has not asked for, so a beta can sit beside a
 stable release without anyone on the stable one ever being offered it.

 Read from the version rather than written here, exactly as the menu's tag is:
 a build that calls itself a beta takes betas, and 1.0 stops taking them without
 anyone remembering to change this. The default channel, which has no name, is
 always allowed and needs no mention.
 */
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    /**
     Told what the last check found, nil for nothing. Set after init, because
     the controller owns this object and cannot hand itself over while it is
     being built, and read from Sparkle's callbacks, which arrive on the main
     thread without saying so in their types.
     */
    nonisolated(unsafe) var onResult: (@MainActor @Sendable (String?) -> Void)?

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

        return version.localizedCaseInsensitiveContains("beta") ? ["beta"] : []
    }

    /** Called for a check the user asked for as well, which is right: it is still what is there. */
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        report(item.displayVersionString)
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        report(nil)
    }

    /**
     Every callback here arrives on the main thread, which the protocol does not
     say in a way the compiler can use. Nothing but a string crosses, so there is
     nothing for a second thread to race over even if that were ever untrue.
     */
    private nonisolated func report(_ version: String?) {
        let onResult = onResult
        MainActor.assumeIsolated { onResult?(version) }
    }
}
