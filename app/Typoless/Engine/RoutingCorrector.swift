import Foundation

/**
 Sends each chunk to whichever model that language is set to use.

 The two backends are good at different things. Apple's model is faster and
 needs no download; a downloaded model scores better on German. Which one should
 answer is therefore a per-language question, and it was previously a single
 global switch: the app built one backend or the other, and a language could
 only name a downloaded model, and only when the global switch already said
 downloaded. A language could not ask for Apple's model at all.

 Routing belongs here rather than inside either backend. Both of them already
 share the chunking, the guardrail and the diff, so the only thing that differs
 between them is which one answers one chunk, and that is a decision, not a
 pipeline. Keeping it out of the backends also means neither has to know the
 other exists.

 A chunk is a line, so this is as fine as routing can usefully be: the language
 is detected per chunk, which puts 98.6% of characters in a bilingual field at
 the right model, against 52.5% for one decision per field. Going finer costs
 accuracy rather than buying it, since a word is too little text to recognise a
 language from.
 */
actor RoutingCorrector: Corrector {
    /** What answers a language that names no model of its own. */
    private let defaultChoice: ModelChoice
    private let detector: LanguageDetector
    private let appliesGuardrail: Bool

    private let apple: FoundationModelsCorrector

    /**
     Built on first use rather than up front.

     A downloaded model brings gigabytes of machinery with it, and most
     configurations never name one. Making it lazily also keeps its download
     reporting wired to whoever built this, rather than to whichever chunk
     happened to need it first.
     */
    private let makeLocal: @Sendable () -> LocalModelCorrector
    private var local: LocalModelCorrector?

    /** Which models answered the current or most recent pass, for the history. */
    private var answered: [ModelChoice] = []

    init(
        defaultChoice: ModelChoice,
        detector: LanguageDetector = LanguageDetector(),
        appliesGuardrail: Bool = true,
        apple: FoundationModelsCorrector? = nil,
        makeLocal: @escaping @Sendable () -> LocalModelCorrector
    ) {
        self.defaultChoice = defaultChoice
        self.detector = detector
        self.appliesGuardrail = appliesGuardrail
        self.apple = apple ?? FoundationModelsCorrector(
            detector: detector,
            appliesGuardrail: appliesGuardrail
        )
        self.makeLocal = makeLocal
    }

    func corrections(for text: String, settings: AppSettings) async throws -> [TextEdit] {
        let deadline = deadline(for: settings)
        answered = []

        return try await ChunkedCorrection.run(
            over: text,
            settings: settings,
            detector: detector,
            appliesGuardrail: appliesGuardrail,
            deadline: deadline
        ) { source, language, startsText in
            let choice = settings.model(for: language) ?? self.defaultChoice
            await self.note(choice)

            switch choice {
            case .appleOnDevice:
                return await self.apple.corrected(
                    source,
                    language: language,
                    startsText: startsText,
                    deadline: deadline
                )

            case .local(let model):
                return await self.loadedLocal().corrected(
                    source,
                    language: language,
                    startsText: startsText,
                    model: model
                )
            }
        }
    }

    /**
     A budget only where every chunk can be held to it.

     The limits in `CorrectionDeadline` are measured against Apple's model. A
     downloaded model generates more slowly, and its first request of a session
     waits for its weights to load, which would spend the whole budget before
     anything was asked and then cut every chunk after it. So a pass that could
     reach a downloaded model runs unbounded, as it did before, until there are
     numbers to bound it with.
     */
    private func deadline(for settings: AppSettings) -> CorrectionDeadline? {
        let choices = settings.languages.values.map { $0.model ?? defaultChoice }

        guard choices.allSatisfy({ $0 == .appleOnDevice }), defaultChoice == .appleOnDevice else {
            return nil
        }

        return CorrectionDeadline()
    }

    func modelsInLastPass() -> [String] {
        answered.map(\.displayName)
    }

    private func note(_ choice: ModelChoice) {
        if !answered.contains(choice) { answered.append(choice) }
    }

    private func loadedLocal() -> LocalModelCorrector {
        if let local { return local }

        let built = makeLocal()
        local = built

        return built
    }

    /**
     The downloaded backend, if one has been built.

     Handed out rather than hidden so a caller that needs the weights already in
     memory, such as the comparison in a debug build, does not load a second
     copy of several gigabytes alongside them.
     */
    func loadedLocalCorrector() -> LocalModelCorrector? { local }

    /** Abandons a download in progress without discarding what is already loaded. */
    func cancelLoading() async {
        await local?.cancelLoading()
    }

    /** Frees the weights, which is what switching away from a model has to do. */
    func unload() async {
        guard let local else { return }

        await local.cancelLoading()
        await local.unload()
        self.local = nil
    }

    /** Fetches ahead of time for a model the user has chosen but not yet used. */
    func prepare(_ model: LocalModel) async {
        await loadedLocal().prepare(model)
    }
}
