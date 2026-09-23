import AppKit
import Observation

/**
 The menu bar item, built directly on AppKit.

 SwiftUI's `MenuBarExtra` renders an icon perfectly well but its menu proved
 unreliable here, and the icon it draws cannot be animated, which the progress
 indicator will need. Owning an `NSStatusItem` costs a little more code and
 gives back full control of both.

 The menu is rebuilt every time it opens rather than kept in sync, since it is
 small and its contents depend on state that moves while it is closed.
 */
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let model: AppModel

    /**
     Kept so they can be refreshed while the menu is open.

     A menu builds its items once, when it opens, and never revisits them. Any
     item whose presence or wording depends on something that moves has to be
     updated by hand, or it shows whatever was true at the moment the user
     clicked.
     */
    private weak var headerItem: NSMenuItem?
    private weak var stopDownloadItem: NSMenuItem?

    private let messages = MessagePanel()

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        let menu = NSMenu()
        menu.delegate = self
        /** Otherwise AppKit decides for itself, overriding every `isEnabled` set here. */
        menu.autoenablesItems = false
        statusItem.menu = menu

        updateIcon()
        observeStatus()
        observeMessages()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let status = model.status
        /**
         The app's own mark while it is ready, which is most of the time. The
         other states keep a symbol, since a change of shape is what says
         something needs a look.
         */
        let image = status == .idle
            ? NSImage(named: "MenuBarIcon")
            : NSImage(systemSymbolName: status.symbolName, accessibilityDescription: status.label)
        image?.accessibilityDescription = status.label
        image?.isTemplate = true
        button.image = image
        button.imagePosition = status.badge == nil ? .imageOnly : .imageLeading
        button.title = status.badge.map { " \($0)" } ?? ""
        button.toolTip = status.label

        /**
         An open menu never rebuilds itself, so anything written when it opened
         would sit at whatever was true at that moment: progress that looks
         stalled, or a stop button for a download that has already finished.
         */
        headerItem?.title = headerTitle
        stopDownloadItem?.isHidden = model.downloadProgress == nil
    }

    /**
     Re-registers itself after every change, because observation tracking fires
     once and then forgets.
     */
    private func observeStatus() {
        withObservationTracking {
            _ = model.status
        } onChange: {
            Task { @MainActor [weak self] in
                self?.updateIcon()
                self?.observeStatus()
            }
        }
    }

    /**
     Puts anything the engine has to say under the icon.

     The menu header carries the same words, but nobody opens a menu to find out
     whether the thing they just triggered worked. Without this, a correction
     that could not be written was indistinguishable from one that changed
     nothing, and both looked like the app doing nothing at all.
     */
    private func observeMessages() {
        withObservationTracking {
            _ = model.engine.lastMessage
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let message = model.engine.lastMessage, let button = statusItem.button {
                    messages.show(message, under: button)
                }

                observeMessages()
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        /** Opening the menu answers the same question, at more length. */
        messages.hide()

        menu.removeAllItems()

        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        headerItem = header

        /**
         Directly under what it acts on, rather than adrift among the actions.
         Always added and hidden when idle, so it can appear and disappear while
         the menu is open without rebuilding it.
         */
        let stop = NSMenuItem(title: "Stop Downloading", action: #selector(cancelDownload), keyEquivalent: "")
        stop.target = self
        stop.isHidden = model.downloadProgress == nil
        menu.addItem(stop)
        stopDownloadItem = stop

        /**
         How to fix text, in place of a menu item that would do it. The trigger
         works from the app being typed in, which is where a correction is
         wanted, so the menu only has to say what it is.
         */
        if let triggerHint, model.permissions.isReady, !model.isPaused {
            let hint = NSMenuItem(title: triggerHint, action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        menu.addItem(.separator())

        /**
         No key equivalents here. They would work only while this menu is
         open, so they save nothing over a click.
         */
        add(
            to: menu,
            title: "Undo",
            keyEquivalent: "",
            isEnabled: model.engine.canRevert,
            action: #selector(revertLast)
        )
        /**
         Beside the single undo rather than down with settings, since the two are
         reached for in the same moment and for the same reason.
         */
        add(
            to: menu,
            title: "History…",
            keyEquivalent: "",
            action: #selector(showHistory)
        )

        menu.addItem(.separator())

        /** What corrects, and whether anything does: the two ways to change how it behaves. */
        let modelsItem = NSMenuItem(title: "Models", action: nil, keyEquivalent: "")
        modelsItem.submenu = modelsMenu()
        menu.addItem(modelsItem)

        add(
            to: menu,
            title: model.isPaused ? "Resume" : "Pause",
            keyEquivalent: "",
            isEnabled: model.permissions.isReady || model.isPaused,
            action: #selector(togglePause)
        )

        menu.addItem(.separator())

        add(to: menu, title: "Settings…", keyEquivalent: ",", action: #selector(showSettings))
        add(to: menu, title: "Set Up Typoless…", keyEquivalent: "", action: #selector(showOnboarding))

        #if DEBUG
        /** In a submenu of its own, so a debug build's menu still reads like the real one. */
        let debugItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        debugItem.submenu = debugMenu()
        menu.addItem(debugItem)
        #endif

        menu.addItem(.separator())

        /**
         Beside About rather than beside History, because this is the report
         with no correction behind it: something is wrong, or missing, and there
         is no entry to point at. A report about one correction starts from that
         correction, in the history window.
         */
        add(to: menu, title: "Report a Problem…", keyEquivalent: "", action: #selector(reportProblem))

        add(to: menu, title: "About Typoless", keyEquivalent: "", action: #selector(showAbout))

        /**
         Only where the app was built with a feed and a key. A build that cannot
         install an update should not offer to look for one, since the only
         thing the item could report is a failure the user cannot act on.
         */
        if UpdateController.isConfigured {
            add(
                to: menu,
                title: "Check for Updates…",
                keyEquivalent: "",
                isEnabled: model.updates?.canCheckForUpdates ?? false,
                action: #selector(checkForUpdates)
            )
        }

        add(to: menu, title: "Quit Typoless", keyEquivalent: "q", action: #selector(quit))
    }

    #if DEBUG
    /** Tools for developing the app. Compiled out of a release build entirely. */
    private func debugMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let observing = NSMenuItem(
            title: model.typingObserver.isRunning ? "Stop Observing Typing" : "Observe Typing",
            action: #selector(toggleTypingObservation),
            keyEquivalent: ""
        )
        observing.target = self
        observing.state = model.typingObserver.isRunning ? .on : .off
        menu.addItem(observing)

        /**
         The switch the settings page used to carry. It is here rather than
         there because the only reason to turn the guardrail off is to see what
         a model really returned.
         */
        let guarded = NSMenuItem(
            title: "Strict Mode",
            action: #selector(toggleGuardrail),
            keyEquivalent: ""
        )
        guarded.target = self
        guarded.state = model.preferences.isGuardrailEnabled ? .on : .off
        menu.addItem(guarded)

        add(to: menu, title: "Report Typing Observations", keyEquivalent: "", action: #selector(reportTypingObservations))
        add(to: menu, title: "Flash Overlay", keyEquivalent: "", action: #selector(flashOverlay))
        add(
            to: menu,
            title: "Compare Models (downloads \(model.preferences.localModel.displayName))",
            keyEquivalent: "",
            isEnabled: !model.isComparing,
            action: #selector(compareModels)
        )

        return menu
    }
    #endif

    /**
     "Beta" while the version says so, and nothing once it does not.

     Read from the version rather than written here, so the tag appears in every
     beta build and disappears at 1.0 without anyone remembering to remove it.
     The About panel carries the full version; the menu only needs the word.
     */
    private static var betaTag: String? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

        return version.localizedCaseInsensitiveContains("beta") ? "Beta" : nil
    }

    /** Nil when both triggers are off, since then there is nothing to press. */
    private var triggerHint: String? {
        model.preferences.triggerDescription.map { "\($0) to fix" }
    }

    private var headerTitle: String {
        guard let progress = model.downloadProgress else {
            /**
             The guardrail is not mentioned. It used to add "rewriting allowed"
             whenever it was off, which was worth saying while that was a switch
             on the settings page. It is not one any more: a shipped build is
             always guarded, and the only way to turn it off is a debug menu
             item that shows its own state.
             */
            let state = model.engine.lastMessage ?? model.status.label

            return [state, Self.betaTag].compactMap { $0 }.joined(separator: " · ")
        }

        /** Same wording as the badge, so the two never disagree. */
        let amount = AppStatus.percentage(progress) ?? "starting…"
        let name = model.activeDownload?.model.displayName ?? model.preferences.localModel.displayName

        return "Downloading \(name) — \(amount)"
    }

    /**
     Lets a different model be tried without leaving the keyboard.

     Picking one here overrides the default rather than replacing it, so the
     first entry names the default and is what the menu returns to. Without it
     there is no way back short of opening settings, and no way to tell that the
     other entries are temporary at all.

     Apple's model is always present; the others are fetched on first use, so
     each says what it will cost before it is picked.
     */
    private func modelsMenu() -> NSMenu {
        let menu = NSMenu()
        /** Same reason as the root menu: AppKit otherwise overrides `isEnabled`. */
        menu.autoenablesItems = false

        let useDefault = NSMenuItem(
            title: "Use Default Model (\(model.defaultModel.displayName))",
            action: #selector(useDefaultModel),
            keyEquivalent: ""
        )
        useDefault.target = self
        useDefault.state = model.modelOverride == nil ? .on : .off
        menu.addItem(useDefault)

        menu.addItem(.separator())

        add(to: menu, override: .appleOnDevice, title: CorrectorBackend.appleOnDevice.displayName)

        for local in LocalModel.allCases {
            /** What it costs, unless it is being paid for right now. */
            let suffix = model.activeDownload?.model == local
                ? " — downloading"
                : " (\(local.approximateSize))"

            add(to: menu, override: .local(local), title: "\(local.displayName)\(suffix)")
        }

        return menu
    }

    private func add(to menu: NSMenu, override choice: ModelChoice, title: String) {
        let item = NSMenuItem(title: title, action: #selector(overrideModel(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = choice
        /** Ticked only when overriding, so exactly one row in the submenu ever is. */
        item.state = model.modelOverride == choice ? .on : .off
        menu.addItem(item)
    }

    private func add(
        to menu: NSMenu,
        title: String,
        keyEquivalent: String,
        isEnabled: Bool = true,
        action: Selector
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = isEnabled
        menu.addItem(item)
    }

    @objc private func revertLast() {
        Task { await model.engine.revertLast() }
    }

    @objc private func cancelDownload() {
        model.cancelDownload()
    }

    @objc private func useDefaultModel() {
        model.override(with: nil)
    }

    @objc private func overrideModel(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ModelChoice else { return }
        model.override(with: choice)
    }

    @objc private func togglePause() {
        model.isPaused.toggle()
    }

    @objc private func showAbout() {
        AboutPanel.show()
    }

    /**
     Opens a prefilled issue with nothing in it but the versions and the model.

     No confirmation here, unlike a report about a correction: there is no text
     of the user's in it, so there is nothing to warn about beyond the tracker
     being public, which the page itself makes plain.
     */
    @objc private func reportProblem() {
        let report = ProblemReport(model: model.activeModel.displayName, environment: .current)

        guard let url = report.url else { return }

        NSWorkspace.shared.open(url)
    }

    @objc private func checkForUpdates() {
        model.updates?.checkForUpdates()
    }

    @objc private func showSettings() {
        model.showSettings()
    }

    @objc private func showHistory() {
        model.showHistory()
    }

    @objc private func showOnboarding() {
        model.showOnboarding()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    #if DEBUG
    @objc private func toggleGuardrail() {
        model.preferences.isGuardrailEnabled.toggle()
    }

    @objc private func toggleTypingObservation() {
        let observer = model.typingObserver
        observer.isRunning ? observer.stop() : observer.start()
    }

    /**
     Shown rather than logged, since the whole point is to read the table and
     decide something. It is also written to the log, so a long run can be
     recovered after the window is gone.
     */
    @objc private func reportTypingObservations() {
        let report = model.typingObserver.report()
        Log.app.info("Typing observations:\n\(report, privacy: .public)")

        /** Monospaced, or the columns do not line up and the table is unreadable. */
        let table = NSTextField(labelWithString: report)
        table.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        table.sizeToFit()

        let alert = NSAlert()
        alert.messageText = "Typing observations"
        alert.accessoryView = table
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Reset")

        if alert.runModal() == .alertSecondButtonReturn {
            model.typingObserver.reset()
        }
    }

    @objc private func compareModels() {
        Task { await model.compareBackends() }
    }

    /**
     Drops the overlay over the centre of the primary screen for a moment, which
     is the only way to check layering and click-through without a text field to
     aim at.
     */
    @objc private func flashOverlay() {
        guard let screen = NSScreen.screens.first else { return }

        /** Three stacked rects, standing in for wrapped lines of text. */
        let origin = CGPoint(x: screen.frame.midX - 180, y: screen.frame.midY - 30)
        let rects = (0..<3).map { line in
            CGRect(
                x: origin.x,
                y: origin.y + CGFloat(line) * 22,
                width: line == 1 ? 240 : 360,
                height: 18
            )
        }

        model.overlay.show(over: rects)

        Task {
            try? await Task.sleep(for: .seconds(3))
            model.overlay.hide()
        }
    }
    #endif
}
