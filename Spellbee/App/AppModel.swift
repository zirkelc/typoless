import Observation
import SwiftUI

/** Keys for values persisted in user defaults. */
enum DefaultsKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let correctorBackend = "correctorBackend"
    static let localModel = "localModel"
    static let guardrailEnabled = "guardrailEnabled"
}

/**
 Root application state. Owns the long-lived pieces and derives the single
 status value the menu bar renders.
 */
@MainActor
@Observable
final class AppModel {
    let permissions = PermissionsModel()
    let overlay = OverlayController()
    let engine: CorrectionEngine

    /** User-initiated pause, cleared manually. */
    var isPaused = false {
        didSet { updateTriggers() }
    }

    /** Which model does the correcting, and which downloaded one if not Apple's. */
    private(set) var backend: CorrectorBackend
    private(set) var localModel: LocalModel

    /** Set while weights are being fetched, from 0 to 1. */
    private(set) var downloadProgress: Double?

    /** Set while both backends are being run over the same samples. */
    private(set) var isComparing = false

    /**
     Whether the model's changes are judged before being applied.

     On by default, and the thing that makes this a correction tool rather than
     a rewriting one. Off, whatever the model returns goes straight into the
     field, which is useful for judging a model and risky for everything else.
     */
    private(set) var isGuardrailEnabled: Bool

    /** Set by whoever owns the window, so the model never touches AppKit itself. */
    @ObservationIgnored var onShowOnboarding: (() -> Void)?

    @ObservationIgnored private let modifierTaps = ModifierTapMonitor()
    @ObservationIgnored private let hotKey = HotKeyMonitor()
    @ObservationIgnored private var isListening = false

    var status: AppStatus {
        if let downloadProgress { return .downloading(downloadProgress) }
        if !permissions.isReady { return .needsAttention }
        if isPaused { return .paused }
        if engine.isRunning { return .working }
        return .idle
    }

    init() {
        let defaults = UserDefaults.standard
        backend = defaults.string(forKey: DefaultsKey.correctorBackend)
            .flatMap(CorrectorBackend.init) ?? .appleOnDevice
        /**
         Gemma by default because it is the one that measures well: it leads
         fix recall by roughly 15 points over Apple's on-device model in both
         languages. Anyone who had a since-removed model selected lands here
         too, since an unknown name reads back as nil.
         */
        localModel = defaults.string(forKey: DefaultsKey.localModel)
            .flatMap(LocalModel.init) ?? .gemma4_e4b

        /** Absent means never set, which should mean on rather than off. */
        isGuardrailEnabled = defaults.object(forKey: DefaultsKey.guardrailEnabled) as? Bool ?? true

        engine = CorrectionEngine(corrector: FoundationModelsCorrector(), overlay: overlay)

        modifierTaps.onDoubleTap = { [weak self] in self?.trigger() }
        hotKey.onFire = { [weak self] in self?.trigger() }

        /** Revoking a permission mid-session has to disarm the triggers too. */
        permissions.onChange = { [weak self] in self?.updateTriggers() }

        updateTriggers()
        rebuildCorrector()
    }

    /**
     Switches which model corrects text.

     Selecting a downloaded model does not fetch anything on its own. The
     weights arrive on the first correction, which is when the user has actually
     asked for the thing that needs them.
     */
    func use(_ backend: CorrectorBackend, model: LocalModel? = nil) {
        self.backend = backend
        if let model { localModel = model }

        let defaults = UserDefaults.standard
        defaults.set(backend.rawValue, forKey: DefaultsKey.correctorBackend)
        defaults.set(localModel.rawValue, forKey: DefaultsKey.localModel)

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

    func setGuardrailEnabled(_ enabled: Bool) {
        isGuardrailEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.guardrailEnabled)
        rebuildCorrector()
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

        switch backend {
        case .appleOnDevice:
            engine.corrector = FoundationModelsCorrector(appliesGuardrail: isGuardrailEnabled)
        case .local:
            let corrector = LocalModelCorrector(
                model: localModel,
                appliesGuardrail: isGuardrailEnabled
            ) { [weak self] progress in
                Task { @MainActor in self?.downloadProgress = progress }
            }
            engine.corrector = corrector

            /**
             Fetch the weights now rather than on the first correction. Choosing
             a model is the moment the user has decided to pay for it, and a
             multi-minute wait is far worse when it lands on a keystroke that
             was expected to be instant.
             */
            Task { await corrector.prepare() }
        }

        Log.app.info(
            "Correcting with \(self.backendDescription, privacy: .public), guardrail \(self.isGuardrailEnabled ? "on" : "OFF", privacy: .public)"
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
        let local = existing ?? LocalModelCorrector(model: localModel) { [weak self] progress in
            Task { @MainActor in self?.downloadProgress = progress }
        }

        await BackendComparison.run(
            apple: FoundationModelsCorrector(),
            local: local,
            localName: localModel.displayName
        )

        /** Only discard weights this comparison brought in itself. */
        if existing == nil {
            await local.unload()
        }
    }

    var backendDescription: String {
        switch backend {
        case .appleOnDevice: return CorrectorBackend.appleOnDevice.displayName
        case .local: return localModel.displayName
        }
    }

    /**
     Starts listening only once the app can actually do something.

     Watching for triggers while a permission is missing would mean firing into
     a failure the user cannot see, on a keystroke they may not have aimed at us.
     */
    func updateTriggers() {
        let shouldListen = permissions.isReady && !isPaused
        guard shouldListen != isListening else { return }

        isListening = shouldListen
        if shouldListen {
            modifierTaps.start()
            hotKey.start()
            Log.app.info("Triggers armed")
        } else {
            modifierTaps.stop()
            hotKey.stop()
            Log.app.info("Triggers disarmed")
        }
    }

    func trigger() {
        Task { await engine.run() }
    }

    func showOnboarding() {
        onShowOnboarding?()
    }
}
