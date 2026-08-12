import Observation
import SwiftUI

/**
 Root application state. Owns the long-lived pieces and derives the single
 status value the menu bar renders.

 Settings themselves live in `Preferences`. This holds what is true right now
 rather than what the user chose: whether a pass is running, how far a download
 has got, whether the triggers are armed.
 */
@MainActor
@Observable
final class AppModel {
    let preferences = Preferences()
    let permissions = PermissionsModel()
    let overlay = OverlayController()
    let engine: CorrectionEngine

    /** User-initiated pause, cleared manually. */
    var isPaused = false {
        didSet { updateTriggers() }
    }

    /** Set while weights are being fetched, from 0 to 1. */
    private(set) var downloadProgress: Double?

    /** Set while both backends are being run over the same samples. */
    private(set) var isComparing = false

    /** Set by whoever owns the window, so the model never touches AppKit itself. */
    @ObservationIgnored var onShowOnboarding: (() -> Void)?
    @ObservationIgnored var onShowSettings: (() -> Void)?

    @ObservationIgnored private let modifierTaps = ModifierTapMonitor()
    @ObservationIgnored private let hotKey = HotKeyMonitor()
    @ObservationIgnored private var armedTriggers: ArmedTriggers = []

    /** Which triggers are currently listening, so a change only rewires what moved. */
    private struct ArmedTriggers: OptionSet {
        let rawValue: Int
        static let doubleTap = ArmedTriggers(rawValue: 1 << 0)
        static let hotKey = ArmedTriggers(rawValue: 1 << 1)
    }

    var status: AppStatus {
        if let downloadProgress { return .downloading(downloadProgress) }
        if !permissions.isReady { return .needsAttention }
        if isPaused { return .paused }
        if engine.isRunning { return .working }
        return .idle
    }

    init() {
        engine = CorrectionEngine(
            corrector: FoundationModelsCorrector(),
            overlay: overlay,
            preferences: preferences
        )

        modifierTaps.onDoubleTap = { [weak self] in self?.trigger() }
        hotKey.onFire = { [weak self] in self?.trigger() }

        /** Revoking a permission mid-session has to disarm the triggers too. */
        permissions.onChange = { [weak self] in self?.updateTriggers() }

        preferences.onTriggersChanged = { [weak self] in self?.updateTriggers() }
        preferences.onCorrectorChanged = { [weak self] in self?.rebuildCorrector() }

        updateTriggers()
        rebuildCorrector()
    }

    /**
     Switches which model corrects text.

     Selecting a downloaded model fetches it straight away rather than on the
     first correction, since choosing it is the moment the user has decided to
     pay for it.
     */
    func use(_ backend: CorrectorBackend, model: LocalModel? = nil) {
        preferences.backend = backend
        if let model { preferences.localModel = model }

        rebuildCorrector()
    }

    /**
     Gives up on a download.

     Falls back to Apple's model rather than leaving the app pointed at weights
     that are not there, which would fail on the next correction with nothing to
     explain why.
     */
    func cancelDownload() {
        guard downloadProgress != nil else { return }

        if let corrector = engine.corrector as? LocalModelCorrector {
            Task { await corrector.cancelLoading() }
        }

        downloadProgress = nil
        use(.appleOnDevice)
    }

    private func rebuildCorrector() {
        /**
         Stop whatever the previous backend was doing. Without the cancel,
         switching models mid-download leaves the old one still fetching several
         gigabytes that nothing will ever use.
         */
        if let previous = engine.corrector as? LocalModelCorrector {
            Task {
                await previous.cancelLoading()
                await previous.unload()
            }
        }

        downloadProgress = nil

        let detector = LanguageDetector(enabled: Array(preferences.enabledLanguages))
        let appliesGuardrail = preferences.isGuardrailEnabled

        switch preferences.backend {
        case .appleOnDevice:
            engine.corrector = FoundationModelsCorrector(
                detector: detector,
                appliesGuardrail: appliesGuardrail
            )
        case .local:
            let corrector = LocalModelCorrector(
                model: preferences.localModel,
                detector: detector,
                appliesGuardrail: appliesGuardrail
            ) { [weak self] progress in
                Task { @MainActor in self?.downloadProgress = progress }
            }
            engine.corrector = corrector

            Task { await corrector.prepare() }
        }

        Log.app.info(
            "Correcting with \(self.backendDescription, privacy: .public), guardrail \(appliesGuardrail ? "on" : "OFF", privacy: .public)"
        )
    }

    /**
     Runs both backends over the same samples and logs the results.

     Uses its own correctors rather than the engine's, so comparing does not
     disturb whichever backend the user has actually chosen.
     */
    func compareBackends() async {
        guard !isComparing else { return }

        isComparing = true
        defer { isComparing = false }

        /**
         Reuse the backend already in use where possible. Building a second one
         loads a second copy of the same several gigabytes of weights, so the
         machine briefly holds two.
         */
        let existing = engine.corrector as? LocalModelCorrector
        let local = existing ?? LocalModelCorrector(model: preferences.localModel) { [weak self] progress in
            Task { @MainActor in self?.downloadProgress = progress }
        }

        await BackendComparison.run(
            apple: FoundationModelsCorrector(),
            local: local,
            localName: preferences.localModel.displayName
        )

        /** Only discard weights this comparison brought in itself. */
        if existing == nil {
            await local.unload()
        }
    }

    var backendDescription: String {
        switch preferences.backend {
        case .appleOnDevice: return CorrectorBackend.appleOnDevice.displayName
        case .local: return preferences.localModel.displayName
        }
    }

    /**
     Starts listening only once the app can actually do something.

     Watching for triggers while a permission is missing would mean firing into
     a failure the user cannot see, on a keystroke they may not have aimed at us.
     */
    func updateTriggers() {
        let isReady = permissions.isReady && !isPaused

        var wanted: ArmedTriggers = []
        if isReady, preferences.isDoubleTapEnabled { wanted.insert(.doubleTap) }
        if isReady, preferences.isHotKeyEnabled { wanted.insert(.hotKey) }

        /**
         The shortcut can change while it is armed, and a registration is not
         updated in place, so it is torn down and put back.
         */
        if wanted.contains(.hotKey), armedTriggers.contains(.hotKey), hotKey.shortcut != preferences.hotKey {
            hotKey.stop()
            armedTriggers.remove(.hotKey)
        }

        guard wanted != armedTriggers else { return }

        if wanted.contains(.doubleTap), !armedTriggers.contains(.doubleTap) {
            modifierTaps.start()
        } else if !wanted.contains(.doubleTap), armedTriggers.contains(.doubleTap) {
            modifierTaps.stop()
        }

        if wanted.contains(.hotKey), !armedTriggers.contains(.hotKey) {
            hotKey.start(preferences.hotKey)
        } else if !wanted.contains(.hotKey), armedTriggers.contains(.hotKey) {
            hotKey.stop()
        }

        armedTriggers = wanted
        Log.app.info("Triggers armed: \(String(describing: wanted.rawValue), privacy: .public)")
    }

    func trigger() {
        Task { await engine.run() }
    }

    func showOnboarding() {
        onShowOnboarding?()
    }

    func showSettings() {
        onShowSettings?()
    }
}
