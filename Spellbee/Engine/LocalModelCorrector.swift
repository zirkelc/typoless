import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/**
 Corrects text with a downloaded model running through MLX.

 Exists to answer a question Apple's on-device model raised rather than settled:
 how much of what it gets wrong is the model, and how much is the task. Both
 backends are given the same instructions and both are judged by the same
 guardrail, so the only variable is the weights.

 The model is several gigabytes and is fetched on first use, so nothing here
 happens until the user asks for it.
 */
actor LocalModelCorrector: Corrector {
    private let model: LocalModel
    private let detector: LanguageDetector

    /**
     One container per model actually used, loaded on demand.

     A language may name a model of its own, so more than one can be live at
     once. Each is gigabytes, so none is loaded until a correction genuinely
     asks for it, and the usual case of every language sharing one model still
     holds exactly one.
     */
    private var containers: [LocalModel: ModelContainer] = [:]
    private var loading: [LocalModel: Task<ModelContainer, Error>] = [:]

    /** Reports download progress from 0 to 1, and nil once there is nothing to report. */
    /**
     Says which model the progress is about.

     Without the model this reported a per-language download as progress on the
     default one, so the menu bar and the settings row both named a model that
     was already on disk and idle, while the one actually downloading appeared
     nowhere.
     */
    private let onProgress: @Sendable (LocalModel, Double?) -> Void

    /** See `FoundationModelsCorrector.appliesGuardrail`. */
    private let appliesGuardrail: Bool

    init(
        model: LocalModel,
        detector: LanguageDetector = LanguageDetector(),
        appliesGuardrail: Bool = true,
        onProgress: @escaping @Sendable (LocalModel, Double?) -> Void = { _, _ in }
    ) {
        self.model = model
        self.detector = detector
        self.appliesGuardrail = appliesGuardrail
        self.onProgress = onProgress
    }

    func corrections(for text: String, settings: AppSettings) async throws -> [TextEdit] {
        try await ChunkedCorrection.run(
            over: text,
            settings: settings,
            detector: detector,
            appliesGuardrail: appliesGuardrail,
            deadline: nil
        ) { source, language, startsText in
            /** A language may prefer a different model from the default. */
            let chosen = settings.model(for: language) ?? self.model
            let container = try await self.loadedContainer(for: chosen)

            return await self.corrected(source, language: language, startsText: startsText, model: chosen, using: container)
        }
    }


    /** Fetches the weights ahead of any correction, so the wait is not a surprise. */
    func prepare() async {
        do {
            _ = try await loadedContainer(for: model)
        } catch is CancellationError {
            /** Asked for by the user, so not worth reporting as a failure. */
        } catch {
            /**
             Worth saying out loud. Swallowing this leaves the app looking like
             it is still downloading something that has already given up.
             */
            Log.app.error(
                "Could not load \(self.model.displayName, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    /** Downloads the weights the first time, then keeps them resident. */
    private func loadedContainer(for model: LocalModel) async throws -> ModelContainer {
        if let container = containers[model] { return container }

        /**
         Two calls arriving together would otherwise start two downloads of the
         same several gigabytes.
         */
        if let existing = loading[model] {
            return try await withTaskCancellationHandler {
                try await existing.value
            } onCancel: {
                existing.cancel()
            }
        }

        let name = model.displayName
        let startedAt = generation
        Log.app.info("Loading \(name, privacy: .public)")

        let report = onProgress

        /**
         Only announce a download when there is one to announce.

         Weights already on disk still take seconds to read into memory, and
         reporting zero before that made switching to a model that was already
         here show a progress bar sitting at nothing. The two look identical
         from in here; the difference is whether the files exist.
         */
        let isFetching = !model.isDownloaded
        if isFetching { report(model, 0) }

        /**
         The hub client hands over its `Progress` once and then updates that
         same object as files arrive, rather than calling back repeatedly.
         Reading the fraction inside the handler therefore always sees zero, and
         the download looks stalled while it is in fact running. So keep the
         object and sample it.
         */
        let tracker = ProgressTracker()
        let configuration = model.configuration

        let task = Task<ModelContainer, Error> {
            try await #huggingFaceLoadModelContainer(configuration: configuration) { progress in
                tracker.track(progress)
            }
        }
        loading[model] = task

        /**
         The poller emits the closing nil itself, and is awaited below.

         Cancelling it and reporting nil from here raced: a poller already
         inside `report` cannot be preempted, so its fraction could land *after*
         the nil and pin the badge at 98% with nothing left to move it. Progress
         then comes from exactly one task, in order, with the nil always last.
         */
        let poller = Task {
            defer { if isFetching { report(model, nil) } }

            while !Task.isCancelled, isFetching {
                if let fraction = tracker.fraction {
                    report(model, fraction)
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }

        /** Only clear the slot if it is still this load, not a newer one. */
        defer {
            if loading[model] == task { loading[model] = nil }
        }

        /**
         Awaiting another task's value does not throw when *this* task is
         cancelled, so Escape during a first-run download reached nothing: the
         key was claimed system-wide for the whole fetch, did nothing anywhere
         on the machine for the minutes it took, and the correction ran at the
         end regardless. The cancellation has to be handed on explicitly.
         */
        let loaded = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        poller.cancel()
        await poller.value

        /**
         Only if this corrector still wants the model. `unload` may have run
         while these gigabytes were arriving, and storing them afterwards left a
         copy resident in an object nothing references and which can never be
         asked to release it.
         */
        guard generation == startedAt else {
            Log.app.info("Discarded \(name, privacy: .public), no longer wanted")
            throw CancellationError()
        }

        containers[model] = loaded
        Log.app.info("Loaded \(name, privacy: .public)")

        return loaded
    }

    /** Abandons a download in progress. */
    func cancelLoading() {
        generation += 1

        for task in loading.values { task.cancel() }
        loading.removeAll()
        Log.app.info("Cancelled loading \(self.model.displayName, privacy: .public)")
    }

    /** Releases the weights, which are the largest thing this app ever holds. */
    func unload() {
        /**
         Bumped so a load already in flight knows not to store its result here.
         Emptying the dictionary alone did nothing to stop several gigabytes
         arriving a moment later and being put straight back in.
         */
        generation += 1

        for task in loading.values { task.cancel() }
        loading.removeAll()
        containers.removeAll()
    }

    /**
     Incremented whenever the corrector is told to let go of everything.

     A load that finishes after that belongs to a corrector nobody is using, and
     storing its weights would leave a copy resident with no way to reach it.
     */
    private var generation = 0

    private func corrected(
        _ text: String,
        language: CorrectionLanguage,
        startsText: Bool,
        model: LocalModel,
        using container: ModelContainer
    ) async -> String? {
        let session = ChatSession(
            container,
            instructions: language.instructions(startsText: startsText),
            generateParameters: GenerateParameters(temperature: 0)
        )

        /**
         An instructed model given a bare sentence tends to answer it rather
         than correct it. Naming the reply's shape keeps it on task, and the
         guardrail catches it when that fails.
         */
        var prompt = language.prompt(for: text)
        prompt += "\n\nReply with the corrected text only, on a single line, with no explanation."
        if model.usesThinkingBlocks {
            prompt += " /no_think"
        }

        do {
            let reply = try await session.respond(to: prompt)
            let cleaned = ModelReplyCleaner.clean(reply, of: text)

            /**
             An empty reply is a failure, not an instruction to delete the line.
             With the guardrail on it was refused; with it off, which is a
             setting the user can reach, the whole chunk was removed from their
             text.
             */
            guard cleaned.contains(where: \.isLetter) else {
                Log.app.info("Model returned nothing usable")
                return nil
            }

            return cleaned
        } catch {
            Log.app.info("Local model failed a chunk: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /**
     Holds the download's `Progress` so it can be sampled from elsewhere.

     `Progress` is safe to read from any thread, but it is handed over on the
     main actor and read from a background task, so the reference itself is
     guarded.
     */
    private final class ProgressTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var progress: Progress?

        func track(_ progress: Progress) {
            lock.lock()
            defer { lock.unlock() }
            self.progress = progress
        }

        var fraction: Double? {
            lock.lock()
            let progress = self.progress
            lock.unlock()
            return progress?.fractionCompleted
        }
    }

}
