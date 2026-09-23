import Foundation

/**
 The correction pass, wired so the prompt and the guardrail can be varied.

 This mirrors what `FoundationModelsCorrector` and `LocalModelCorrector` do,
 step for step, and reuses the same `TextChunker`, `LanguageDetector`,
 `TextDiff`, `ProtectedSpans` and `EditGuardrail`. It is not the app's own loop
 because both correctors read the prompt straight out of `CorrectionLanguage`
 and neither takes one as an argument, so sweeping variants through them is not
 possible without changing files this harness does not own.

 It adds two things. It counts what the guardrail threw away, which is invisible
 from the outside once a chunk has been dropped. And it produces the guarded and
 unguarded results from the same replies, because the guardrail is pure
 post-processing: asking the model twice would double the cost of a run and
 leave the two numbers describing different samples.
 */
struct EvalPipeline: Sendable {
    let backend: any EvalBackend
    let variant: PromptVariant
    /** False shows the model the links and handles, which is what the app used to do. */
    let masks: Bool
    /** False lets a stuck request run, which is what the app used to do. */
    let appliesDeadline: Bool

    /** Rules the user has switched off. Empty is the app's own configuration. */
    var disabledRules: Set<CorrectionRule> = []

    /** Whether the prompt names the rules that are off, which is the thing under test. */
    var tellsModel = false

    let detector = LanguageDetector()

    struct Outcome: Sendable {
        var text: String
        /** Chunks thrown away whole, because more was refused than accepted or the language changed. */
        var chunksDropped = 0
        /** Individual changes refused, whether or not their chunk survived. */
        var editsRejected = 0
        /** Chunks the model would not answer at all, which are left as written. */
        var modelDeclined = 0
        /** Chunks asked about twice because the markers did not survive the first reply. */
        var maskRetries = 0
        /**
         Changes the model proposed that touch a rule the user switched off.

         Counted before the guardrail sees them, so it says what the model did
         rather than what survived. It is the whole point of telling the model:
         with the prompt silent this is what a switched-off rule costs, either
         as a change the user did not want (strict mode off) or as a wanted fix
         thrown away with it (strict mode on).
         */
        var offRuleEdits = 0
        /**
         Of those, the ones that also carry a rule the user still wants.

         `TextDiff` merges neighbouring changes, so restoring an umlaut and
         adding a comma can arrive as one edit. The filter judges an edit by the
         whole set, so a single switched-off rule takes the wanted fix with it.
         This counts how often that happens before anything is built to stop it.
         */
        var mixedOffRuleEdits = 0
    }

    struct Pass: Sendable {
        let guarded: Outcome
        let unguarded: Outcome

        subscript(appliesGuardrail: Bool) -> Outcome {
            appliesGuardrail ? guarded : unguarded
        }
    }

    func correct(_ text: String) async -> Pass {
        let protected = ProtectedSpans.find(in: text)

        /** The same budget the app gives a pass, for the backends it applies to. */
        let deadline = backend.hasDeadline && appliesDeadline ? CorrectionDeadline() : nil

        var guardedEdits: [TextEdit] = []
        var unguardedEdits: [TextEdit] = []
        var guarded = Outcome(text: text)
        var unguarded = Outcome(text: text)

        for chunk in TextChunker.chunks(of: text) {
            guard deadline?.hasExpired() != true else { break }

            let source = String(text[chunk])

            /** Only the opening chunk is told about an opening capital, as the app does. */
            let startsText = chunk.lowerBound == text.startIndex

            /** Same masking the app does, so the numbers describe the app. */
            let masked = MaskedText.mask(source, protecting: masks ? ProtectedSpans.find(in: source) : [])

            guard masked.text.contains(where: \.isLetter) else { continue }

            /**
             The detector answers only with languages the run has enabled, so a
             chunk it cannot place is one the app would leave exactly as
             written. Counted as a decline, since nothing came back for it.
             */
            guard let language = detector.detect(masked.text) else {
                guarded.modelDeclined += 1
                unguarded.modelDeclined += 1
                continue
            }

            /** Masked first, then as written if the markers did not survive, as the app does. */
            var answered = await answer(for: masked.text, language: language, startsText: startsText, within: deadline)
                .flatMap(masked.restore)

            if answered == nil, !masked.hidesNothing, deadline?.hasExpired() != true {
                answered = await answer(for: source, language: language, startsText: startsText, within: deadline)
                guarded.maskRetries += 1
                unguarded.maskRetries += 1
            }

            guard let corrected = answered else {
                guarded.modelDeclined += 1
                unguarded.modelDeclined += 1
                continue
            }

            let chunkEdits = TextDiff.edits(from: source, to: corrected)
                .map { rebase($0, from: source, into: text, at: chunk) }

            unguardedEdits += chunkEdits

            /** Both outcomes get the same count: it describes the reply, not the filtering. */
            if !disabledRules.isEmpty {
                var offRule = 0
                var mixed = 0

                for edit in chunkEdits {
                    guard let kinds = EditGuardrail.classify(edit, in: text, language: language),
                          !kinds.isDisjoint(with: disabledRules)
                    else { continue }

                    offRule += 1
                    if !kinds.subtracting(disabledRules).isEmpty { mixed += 1 }
                }

                guarded.offRuleEdits += offRule
                unguarded.offRuleEdits += offRule
                guarded.mixedOffRuleEdits += mixed
                unguarded.mixedOffRuleEdits += mixed
            }

            if detector.detect(corrected) != language || EditGuardrail.isShouting(corrected, over: source) {
                guarded.chunksDropped += 1
                guarded.editsRejected += chunkEdits.count
                continue
            }

            let verdict = EditGuardrail.filter(
                chunkEdits,
                in: text,
                allowing: Set(CorrectionRule.allCases).subtracting(disabledRules),
                protectedBy: protected,
                language: language
            )
            guarded.editsRejected += verdict.rejectedCount

            guard verdict.isTrustworthy else {
                guarded.chunksDropped += 1
                continue
            }

            guardedEdits += verdict.accepted
        }

        guarded.text = TextDiff.apply(guardedEdits, to: text)
        unguarded.text = TextDiff.apply(unguardedEdits, to: text)

        return Pass(guarded: guarded, unguarded: unguarded)
    }

    /**
     The variant's wording, with the switched-off rules named after it when the
     arm under test says so.

     Said last on purpose. The sweeps found that whatever comes last is what
     this model does, which is why the protection list had to move to the top:
     read last, "leave this as it is" became advice about the whole text. A
     prohibition is meant to be read that way round, so it goes where the
     emphasis is.
     */
    private func instructions(_ language: CorrectionLanguage, _ startsText: Bool) -> String {
        let body = variant.instructions(language, startsText)
        guard tellsModel else { return body }

        return body + RuleExclusions.text(for: disabledRules, in: language)
    }

    private func answer(
        for source: String,
        language: CorrectionLanguage,
        startsText: Bool,
        within deadline: CorrectionDeadline?
    ) async -> String? {
        let first = await backend.reply(
            instructions: instructions(language, startsText),
            prompt: variant.userPrompt(language, source, backend.usesGuidedGeneration),
            freeTextSuffix: variant.freeTextSuffix,
            within: deadline?.allowance()
        )

        if let first { return first }
        guard language != .english, deadline?.hasExpired() != true else { return nil }

        return await backend.reply(
            instructions: instructions(.english, startsText),
            prompt: variant.retryPrompt(language, source),
            freeTextSuffix: variant.freeTextSuffix,
            within: deadline?.allowance()
        )
    }

    /** Moves an edit's range from the chunk it was found in to the full text. */
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
