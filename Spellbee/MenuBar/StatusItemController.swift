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

    func menuNeedsUpdate(_ menu: NSMenu) {
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
            isEnabled: model.permissions.isReady && !model.engine.isRunning,
            action: #selector(fixNow)
        )
        add(
            to: menu,
            title: "Revert Last Fix",
            keyEquivalent: "z",
            isEnabled: model.engine.canRevert,
            action: #selector(revertLast)
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

        let engineItem = NSMenuItem(title: "Correction Model", action: nil, keyEquivalent: "")
        engineItem.submenu = engineMenu()
        menu.addItem(engineItem)

        let guardrail = NSMenuItem(
            title: "Only Fix, Never Rewrite",
            action: #selector(toggleGuardrail),
            keyEquivalent: ""
        )
        guardrail.target = self
        guardrail.state = model.isGuardrailEnabled ? .on : .off
        guardrail.toolTip = model.isGuardrailEnabled
            ? "Changes that are not spelling, punctuation, capitalisation or spacing are discarded."
            : "Off: whatever the model returns is applied, including rewritten or translated text."
        menu.addItem(guardrail)

        menu.addItem(.separator())

        add(to: menu, title: "Set Up Spellbee…", keyEquivalent: "", action: #selector(showOnboarding))

        #if DEBUG
        add(to: menu, title: "Debug: Flash Overlay", keyEquivalent: "", action: #selector(flashOverlay))
        add(
            to: menu,
            title: "Debug: Compare Models (downloads \(model.localModel.displayName))",
            keyEquivalent: "",
            isEnabled: !model.isComparing,
            action: #selector(compareModels)
        )
        #endif

        menu.addItem(.separator())

        add(to: menu, title: "Quit Spellbee", keyEquivalent: "q", action: #selector(quit))
    }

    private var headerTitle: String {
        guard let progress = model.downloadProgress else {
            let state = model.engine.lastMessage ?? model.status.label

            /** Never let an unguarded state be a silent one. */
            return model.isGuardrailEnabled ? state : "\(state) — rewriting allowed"
        }

        /** Same wording as the badge, so the two never disagree. */
        let amount = AppStatus.percentage(progress) ?? "starting…"
        return "Downloading \(model.localModel.displayName) — \(amount)"
    }

    /**
     Lets the two backends be compared without a rebuild.

     Apple's model is always present; the others are fetched on first use, so
     each says what it will cost before it is picked.
     */
    private func engineMenu() -> NSMenu {
        let menu = NSMenu()

        let apple = NSMenuItem(
            title: CorrectorBackend.appleOnDevice.displayName,
            action: #selector(useAppleModel),
            keyEquivalent: ""
        )
        apple.target = self
        apple.state = model.backend == .appleOnDevice ? .on : .off
        menu.addItem(apple)

        menu.addItem(.separator())

        for local in LocalModel.allCases {
            let isSelected = model.backend == .local && model.localModel == local
            let suffix = isSelected && model.downloadProgress != nil
                ? " — downloading"
                : " (\(local.approximateSize))"

            let item = NSMenuItem(
                title: "\(local.displayName)\(suffix)",
                action: #selector(useLocalModel(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = local.rawValue
            item.state = isSelected ? .on : .off
            menu.addItem(item)
        }

        return menu
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

    @objc private func toggleGuardrail() {
        model.setGuardrailEnabled(!model.isGuardrailEnabled)
    }

    @objc private func cancelDownload() {
        model.cancelDownload()
    }

    @objc private func useAppleModel() {
        model.use(.appleOnDevice)
    }

    @objc private func useLocalModel(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let choice = LocalModel(rawValue: raw)
        else {
            return
        }
        model.use(.local, model: choice)
    }

    @objc private func togglePause() {
        model.isPaused.toggle()
    }

    @objc private func showOnboarding() {
        model.showOnboarding()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    #if DEBUG
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
