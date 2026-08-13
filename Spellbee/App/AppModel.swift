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

    /**
     Fetches in flight, from 0 to 1, keyed by model.

     Keyed rather than single, because the settings window can start a download
     for a model that is not the one in use, and two can be running at once.
     */
    private(set) var downloads: [LocalModel: Double] = [:]

    /** The one worth showing in the menu bar, which is whichever is furthest along. */
    var downloadProgress: Double? {
        downloads.values.max()
    }

    /**
     Models being read into memory right now.

     Separate from `downloads`, because weights already on disk still take
     seconds to load and that is not a download. Showing a progress bar for it
     claimed a transfer that was not happening; showing nothing at all left a
     click with no answer for several seconds.
     */
    private(set) var loading: Set<LocalModel> = []

    /** Set while both backends are being run over the same samples. */
    private(set) var isComparing = false

    /** Set by whoever owns the window, so the model never touches AppKit itself. */
    @ObservationIgnored var onShowOnboarding: (() -> Void)?
    @ObservationIgnored var onShowSettings: (() -> Void)?

    /** Correctors that exist only to fetch weights, discarded once they have. */
    @ObservationIgnored private var fetchers: [LocalModel: LocalModelCorrector] = [:]

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

        for fetcher in fetchers.values {
            Task { await fetcher.cancelLoading() }
        }
        fetchers.removeAll()

        downloads.removeAll()
        use(.appleOnDevice)
    }

    /**
     Fetches a model's weights without selecting it.

     Choosing a model and having it start downloading is one behaviour; wanting
     the download done before it is needed is another, and the settings window
     offers the second. Each fetch gets its own corrector so it does not disturb
     whichever backend is actually in use.
     */
    func download(_ model: LocalModel) {
        guard downloads[model] == nil, !model.isDownloaded else { return }

        let corrector = LocalModelCorrector(model: model) { [weak self] progress in
            Task { @MainActor in
                if let progress {
                    self?.downloads[model] = progress
                } else {
                    self?.downloads[model] = nil
                    self?.fetchers[model] = nil
                }
            }
        }

        fetchers[model] = corrector
        downloads[model] = 0

        Task {
            await corrector.prepare()

            /** Holding the weights here would double what the machine carries. */
            await corrector.unload()
        }
    }

    /**
     Puts a model's weights in the Trash.

     The Trash rather than a delete, because these are gigabytes and the cache
     is shared with every other MLX app on the machine, so getting this wrong
     silently costs someone else a download too. Recoverable is the right
     default for that.
     */
    func remove(_ model: LocalModel) throws {
        cancelDownload(of: model)

        var trashed: NSURL?
        try FileManager.default.trashItem(at: model.cacheDirectory, resultingItemURL: &trashed)

        /** Pointing at weights that are gone would fail on the next keystroke. */
        if preferences.backend == .local, preferences.localModel == model {
            use(.appleOnDevice)
        }

        for (language, settings) in preferences.languageSettings where settings.model == model {
            var updated = preferences.languageSettings
            updated[language]?.model = nil
            preferences.languageSettings = updated
        }

        Log.app.info("Removed \(model.displayName, privacy: .public)")
    }

    func cancelDownload(of model: LocalModel) {
        guard let corrector = fetchers[model] else { return }

        Task { await corrector.cancelLoading() }
        fetchers[model] = nil
        downloads[model] = nil
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

        let detector = LanguageDetector(enabled: Array(preferences.enabledLanguages))
        let appliesGuardrail = preferences.isGuardrailEnabled

        switch preferences.backend {
        case .appleOnDevice:
            engine.corrector = FoundationModelsCorrector(
                detector: detector,
                appliesGuardrail: appliesGuardrail
            )
        case .local:
            let selected = preferences.localModel
            let corrector = LocalModelCorrector(
                model: selected,
                detector: detector,
                appliesGuardrail: appliesGuardrail
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.downloads[selected] = progress
                }
            }
            engine.corrector = corrector

            loading.insert(selected)
            Task {
                await corrector.prepare()
                loading.remove(selected)
            }
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
        let selected = preferences.localModel
        let existing = engine.corrector as? LocalModelCorrector
        let local = existing ?? LocalModelCorrector(model: selected) { [weak self] progress in
            Task { @MainActor in self?.downloads[selected] = progress }
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

        /**
         Set before the early return below, because which key is tapped can
         change while the monitor is already armed, and that change on its own
         leaves the set of armed triggers untouched.
         */
        modifierTaps.modifier = preferences.doubleTapModifier

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
