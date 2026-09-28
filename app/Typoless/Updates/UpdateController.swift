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

 **Nothing is installed until the user says so.** Checking is on from the
 first launch, because a check is one request a day carrying the app's name and
 version, and the promise this app makes is about the text you type, not about
 a version number. It never sends the profile of the Mac that Sparkle can
 attach, because the app never offers it. What happens when an update is found
 is the answer that matters, and it defaults to asking: the app says so in the
 menu and installs nothing until the button is pressed. Both can be changed in
 General settings.

 **An update announces itself quietly.** Sparkle would otherwise put its window
 in front of whatever the user is writing, which for an app that lives in the
 menu bar is an interruption with no relation to what they are doing. The
 gentle reminder API hands that decision here instead: the found update is kept,
 the menu bar marks itself, and Sparkle's window opens when the user asks for
 it.
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

    /** Held for the same reason as the channel answer: Sparkle keeps neither. */
    @ObservationIgnored private let reminders = ReminderDelegate()

    /**
     The version Sparkle has found and not shown, or nil when there is nothing
     to tell. What the menu bar reads to decide whether to mark itself.

     A version string rather than the update itself, because this crosses from
     Sparkle's callback to the main actor and a string is the whole of what the
     menu has to say.
     */
    private(set) var availableUpdate: String?

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
            userDriverDelegate: reminders
        )
        refresh()

        reminders.onUpdate = { [weak self] version in
            self?.availableUpdate = version

            /**
             The one trace an update leaves before anybody clicks anything.
             Without it, a mark that never appears and a check that found
             nothing look exactly alike from the outside.
             */
            if let version {
                Log.app.info("An update is waiting, version \(version, privacy: .public)")
            }
        }
    }

    func setChecksAutomatically(_ isOn: Bool) {
        updater.updater.automaticallyChecksForUpdates = isOn
        refresh()
    }

    /**
     Whether a found update installs itself.

     Off by default, so an update is something the user agrees to. Sparkle
     ignores this while checking is off, since there is nothing to download when
     nothing is looked for, and the switch is shown as unavailable there rather
     than as a promise the app cannot keep.
     */
    private(set) var installsAutomatically = false

    func setInstallsAutomatically(_ isOn: Bool) {
        updater.updater.automaticallyDownloadsUpdates = isOn
        refresh()
    }

    /** Picks up a change Sparkle made behind our back, which its own UI can. */
    func refresh() {
        let checks = updater.updater.automaticallyChecksForUpdates
        if checksAutomatically != checks { checksAutomatically = checks }

        let installs = updater.updater.automaticallyDownloadsUpdates
        if installsAutomatically != installs { installsAutomatically = installs }
    }

    /**
     What the menu item does, and the only path that reports "you are up to
     date".

     Also what shows an update that was found quietly: Sparkle keeps the one it
     told us about, so this opens its window on that update rather than asking
     the server again.
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

/**
 Where an update that nobody asked to see is handled.

 Sparkle's own behaviour is to show its window as soon as a scheduled check
 finds something. That is right for an app with windows of its own and wrong
 for one that lives in the menu bar: it arrives in the middle of a sentence
 somebody is writing, about something they did not ask for. Returning false
 here makes it Typoless's job to say so, which it does in the place the app
 already lives.
 */
private final class ReminderDelegate: NSObject, SPUStandardUserDriverDelegate {
    /**
     Told what to show, and told to stop. Set after init, because the controller
     owns this object and cannot hand itself over while it is being built, and
     read from Sparkle's callbacks, which arrive on the main thread without
     saying so in their types.
     */
    nonisolated(unsafe) var onUpdate: (@MainActor @Sendable (String?) -> Void)?

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /**
     False, always: the update is announced in the menu bar instead.

     Even in immediate focus, which is Sparkle asking whether the user is
     looking at the app right now. They never are. This app has no window it
     lives in, so there is no moment where its update window is the thing in
     front of somebody by their own choice.
     */
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    /**
     Called whichever way the answer went, so it both raises the mark and clears
     it: Sparkle handling the update itself means the user is already looking at
     it, and a mark in the menu bar would be telling them what is on their
     screen.
     */
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        report(handleShowingUpdate ? nil : update.displayVersionString)
    }

    /** The user has seen it, so there is nothing left to point at. */
    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        report(nil)
    }

    /** Installed, skipped or dismissed: all of them end the same way here. */
    nonisolated func standardUserDriverWillFinishUpdateSession() {
        report(nil)
    }

    /**
     Every callback here arrives on the main thread, which the protocol does not
     say in a way the compiler can use. Nothing but a string crosses, so there is
     nothing for a second thread to race over even if that were ever untrue.
     */
    private nonisolated func report(_ version: String?) {
        let onUpdate = onUpdate
        MainActor.assumeIsolated { onUpdate?(version) }
    }
}
