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
    private let allowedKinds: Set<EditKind>

    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?

    /** Reports download progress from 0 to 1, and nil once there is nothing to report. */
    private let onProgress: @Sendable (Double?) -> Void

    /** See `FoundationModelsCorrector.appliesGuardrail`. */
    private let appliesGuardrail: Bool

    init(
        model: LocalModel,
        detector: LanguageDetector = LanguageDetector(),
        allowedKinds: Set<EditKind> = Set(EditKind.allCases),
        appliesGuardrail: Bool = true,
        onProgress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) {
        self.model = model
        self.detector = detector
        self.allowedKinds = allowedKinds
        self.appliesGuardrail = appliesGuardrail
        self.onProgress = onProgress
    }

    func corrections(for text: String) async throws -> [TextEdit] {
        let container = try await loadedContainer()
        let protected = ProtectedSpans.find(in: text)
        var edits: [TextEdit] = []

        for chunk in TextChunker.chunks(of: text) {
            /** The user can give up mid-pass, and a long field is several chunks. */
            try Task.checkCancellation()

            let source = String(text[chunk])
            guard source.contains(where: \.isLetter) else { continue }

            let language = detector.detect(source)

            guard let corrected = await corrected(source, language: language, using: container) else {
                continue
            }

            if appliesGuardrail, detector.detect(corrected) != language {
                Log.app.info("Dropped a chunk whose language changed")
                continue
            }

            let chunkEdits = TextDiff.edits(from: source, to: corrected)
                .map { rebase($0, from: source, into: text, at: chunk) }

            guard appliesGuardrail else {
                edits += chunkEdits
                continue
            }

            let verdict = EditGuardrail.filter(
                chunkEdits,
                allowing: allowedKinds,
                protectedBy: protected
            )

            guard verdict.isTrustworthy else {
                Log.app.info("Dropped a chunk the local model rewrote rather than corrected")
                continue
            }

            edits += verdict.accepted
        }

        Log.app.info("Found \(edits.count, privacy: .public) edits from \(self.model.displayName, privacy: .public)")
        return edits
    }

    /** Fetches the weights ahead of any correction, so the wait is not a surprise. */
    func prepare() async {
        do {
            _ = try await loadedContainer()
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
    private func loadedContainer() async throws -> ModelContainer {
        if let container { return container }

        /**
         Two calls arriving together would otherwise start two downloads of the
         same several gigabytes.
         */
        if let loading { return try await loading.value }

        let name = model.displayName
        Log.app.info("Loading \(name, privacy: .public)")

        let report = onProgress
        report(0)

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
        loading = task

        let poller = Task {
            while !Task.isCancelled {
                if let fraction = tracker.fraction {
                    report(fraction)
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }

        defer {
            poller.cancel()
            loading = nil
            report(nil)
        }

        let loaded = try await task.value
        container = loaded
        Log.app.info("Loaded \(name, privacy: .public)")

        return loaded
    }

    /** Abandons a download in progress. */
    func cancelLoading() {
        loading?.cancel()
        loading = nil
        Log.app.info("Cancelled loading \(self.model.displayName, privacy: .public)")
    }

    /** Releases the weights, which are the largest thing this app ever holds. */
    func unload() {
        container = nil
    }

    private func corrected(
        _ text: String,
        language: CorrectionLanguage,
        using container: ModelContainer
    ) async -> String? {
        let session = ChatSession(
            container,
            instructions: language.instructions,
            generateParameters: GenerateParameters(temperature: 0)
        )

        /**
         An instructed model given a bare sentence tends to answer it rather
         than correct it. Naming the reply's shape keeps it on task, and the
         guardrail catches it when that fails.
         */
        var prompt = language.prompt(for: text)
        prompt += "\n\nReply with the corrected text only, on a single line, with no explanation and no quotation marks."
        if model.usesThinkingBlocks {
            prompt += " /no_think"
        }

        do {
            let reply = try await session.respond(to: prompt)
            return ModelReplyCleaner.clean(reply)
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

    private func rebase(
        _ edit: TextEdit,
        from chunk: String,
        into text: String,
        at range: Range<String.Index>
    ) -> TextEdit {
        let start = chunk.distance(from: chunk.startIndex, to: edit.range.lowerBound)
        let length = chunk.distance(from: edit.range.lowerBound, to: edit.range.upperBound)

        let lower = text.index(range.lowerBound, offsetBy: start)
        let upper = text.index(lower, offsetBy: length)

        return TextEdit(range: lower..<upper, original: edit.original, replacement: edit.replacement)
    }
}
