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
        button.image = NSImage(
            systemSymbolName: status.symbolName,
            accessibilityDescription: status.label
        )
        button.image?.isTemplate = true
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

        menu.addItem(.separator())

        add(
            to: menu,
            title: "Fix Now",
            keyEquivalent: "f",
            isEnabled: model.permissions.isReady && !model.isPaused && !model.engine.isRunning,
            action: #selector(fixNow)
        )
        add(
            to: menu,
            title: "Undo",
            keyEquivalent: "z",
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
            keyEquivalent: "y",
            action: #selector(showHistory)
        )

        menu.addItem(.separator())

        add(
            to: menu,
            title: model.isPaused ? "Resume" : "Pause",
            keyEquivalent: "",
            isEnabled: model.permissions.isReady || model.isPaused,
            action: #selector(togglePause)
        )

        menu.addItem(.separator())

        let modelsItem = NSMenuItem(title: "Models", action: nil, keyEquivalent: "")
        modelsItem.submenu = modelsMenu()
        menu.addItem(modelsItem)

        menu.addItem(.separator())

        add(to: menu, title: "Settings…", keyEquivalent: ",", action: #selector(showSettings))
        add(to: menu, title: "Set Up Spellbee…", keyEquivalent: "", action: #selector(showOnboarding))

        #if DEBUG
        let observing = NSMenuItem(
            title: model.typingObserver.isRunning
                ? "Debug: Stop Observing Typing"
                : "Debug: Observe Typing",
            action: #selector(toggleTypingObservation),
            keyEquivalent: ""
        )
        observing.target = self
        observing.state = model.typingObserver.isRunning ? .on : .off
        menu.addItem(observing)

        add(
            to: menu,
            title: "Debug: Report Typing Observations",
            keyEquivalent: "",
            action: #selector(reportTypingObservations)
        )

        add(to: menu, title: "Debug: Flash Overlay", keyEquivalent: "", action: #selector(flashOverlay))
        add(
            to: menu,
            title: "Debug: Compare Models (downloads \(model.preferences.localModel.displayName))",
            keyEquivalent: "",
            isEnabled: !model.isComparing,
            action: #selector(compareModels)
        )
        #endif

        menu.addItem(.separator())

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

        add(to: menu, title: "Quit Spellbee", keyEquivalent: "q", action: #selector(quit))
    }

    private var headerTitle: String {
        guard let progress = model.downloadProgress else {
            let state = model.engine.lastMessage ?? model.status.label

            /** Never let an unguarded state be a silent one. */
            return model.preferences.isGuardrailEnabled ? state : "\(state) — rewriting allowed"
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

    @objc private func fixNow() {
        model.trigger()
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
