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

 **Nothing is checked until the user says so.** A check is one request for the
 feed, and it tells the server the app's name and version, which is more than
 an app whose promise is that it keeps to itself should do without asking.
 Sparkle asks on the second launch whether to check automatically, the answer
 can be changed in General settings, and until then it checks only when the
 menu item is used. It never sends the profile of the Mac that Sparkle can
 attach, because the app never offers it.
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

    @ObservationIgnored private let updater: SPUStandardUpdaterController

    /**
     Held here because Sparkle does not retain its delegate.

     Without this property the channel answer would be given by an object that
     has already gone, which is the same as never giving it: a beta build would
     read the feed and find nothing addressed to it.
     */
    @ObservationIgnored private let channels = ChannelDelegate()

    /**
     Whether Sparkle checks on its own, once a day.

     Stored rather than read through, because a computed property is invisible
     to observation and the switch bound to it would never redraw. Sparkle's
     own question on the second launch changes the value behind our back, so
     it is read again whenever settings are shown.
     */
    private(set) var checksAutomatically = false

    init() {
        /**
         `startingUpdater: true` only arms Sparkle. It checks on a schedule once
         the user has said yes, and asks that question itself on the second
         launch.
         */
        updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: channels,
            userDriverDelegate: nil
        )
        refresh()
    }

    func setChecksAutomatically(_ isOn: Bool) {
        updater.updater.automaticallyChecksForUpdates = isOn
        refresh()
    }

    /** Picks up an answer given to Sparkle's own question. */
    func refresh() {
        let current = updater.updater.automaticallyChecksForUpdates
        if checksAutomatically != current { checksAutomatically = current }
    }

    /** What the menu item does, and the only path that reports "you are up to date". */
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

    var lastCheck: Date? {
        updater.updater.lastUpdateCheckDate
    }
}

/**
 Which parts of the feed this build is allowed to see.

 One feed carries every release. An entry may name a channel, and Sparkle
 ignores any channel the build has not asked for, so a beta can sit beside a
 stable release without anyone on the stable one ever being offered it.

 Read from the version rather than written here, exactly as the menu's tag is:
 a build that calls itself a beta takes betas, and 1.0 stops taking them without
 anyone remembering to change this. The default channel, which has no name, is
 always allowed and needs no mention.
 */
private final class ChannelDelegate: NSObject, SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

        return version.localizedCaseInsensitiveContains("beta") ? ["beta"] : []
    }
}
