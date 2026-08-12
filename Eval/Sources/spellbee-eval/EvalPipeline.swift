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
    let detector = LanguageDetector()

    struct Outcome: Sendable {
        var text: String
        /** Chunks thrown away whole, because more was refused than accepted or the language changed. */
        var chunksDropped = 0
        /** Individual changes refused, whether or not their chunk survived. */
        var editsRejected = 0
        /** Chunks the model would not answer at all, which are left as written. */
        var modelDeclined = 0
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

        var guardedEdits: [TextEdit] = []
        var unguardedEdits: [TextEdit] = []
        var guarded = Outcome(text: text)
        var unguarded = Outcome(text: text)

        for chunk in TextChunker.chunks(of: text) {
            let source = String(text[chunk])
            guard source.contains(where: \.isLetter) else { continue }

            let language = detector.detect(source)

            guard let corrected = await answer(for: source, language: language) else {
                guarded.modelDeclined += 1
                unguarded.modelDeclined += 1
                continue
            }

            let chunkEdits = TextDiff.edits(from: source, to: corrected)
                .map { rebase($0, from: source, into: text, at: chunk) }

            unguardedEdits += chunkEdits

            if detector.detect(corrected) != language {
                guarded.chunksDropped += 1
                guarded.editsRejected += chunkEdits.count
                continue
            }

            let verdict = EditGuardrail.filter(chunkEdits, in: text, protectedBy: protected)
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

    private func answer(for source: String, language: CorrectionLanguage) async -> String? {
        let first = await backend.reply(
            instructions: variant.instructions(language),
            prompt: variant.userPrompt(language, source),
            freeTextSuffix: variant.freeTextSuffix
        )

        if let first { return first }
        guard language != .english else { return nil }

        return await backend.reply(
            instructions: variant.retryInstructions(),
            prompt: variant.retryPrompt(language, source),
            freeTextSuffix: variant.freeTextSuffix
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
