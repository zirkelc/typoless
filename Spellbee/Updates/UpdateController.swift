import Foundation
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
 still cannot be installed. A missing or wrong signature is refused, which is
 also why the key below must be filled in before a release: with no key Sparkle
 refuses everything, which is the safe direction to fail in.

 **Nothing is checked or sent until the user says so.** Sparkle's automatic
 checking sends a profile of the machine to the update server, which is a strange
 thing to do silently in an app whose promise is that it keeps to itself. It asks
 on first use instead, and until it is answered this checks only when the menu
 item is used.
 */
@MainActor
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

    private let updater: SPUStandardUpdaterController

    init() {
        /**
         `startingUpdater: true` begins the scheduled checks, which is why the
         automatic ones are turned off in the app's own settings rather than
         here: Sparkle asks the user the first time, and the answer is theirs to
         give and to change.
         */
        updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
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
