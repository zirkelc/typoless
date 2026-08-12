import Foundation
import FoundationModels

/**
 Corrects text with the on-device model.

 The model is asked for one thing only: the corrected sentence. It is never
 asked where its changes are or what kind they were, because those answers would
 have to be trusted, and a model that is confidently wrong about an offset
 corrupts text silently. Instead the two versions are compared here, and every
 difference is judged before it is allowed to happen.

 A chunk that fails is left exactly as the user wrote it. Refusing to correct is
 always better than mangling a message someone is about to send.
 */
actor FoundationModelsCorrector: Corrector {
    private let detector: LanguageDetector
    private let model: SystemLanguageModel
    private let allowedKinds: Set<EditKind>

    /**
     Whether the model's changes are judged before being applied.

     Turning this off applies whatever comes back, including a rephrased or
     translated sentence. It exists so the model can be evaluated on its own
     terms, which the guardrail otherwise obscures.
     */
    private let appliesGuardrail: Bool

    init(
        detector: LanguageDetector = LanguageDetector(),
        allowedKinds: Set<EditKind> = Set(EditKind.allCases),
        appliesGuardrail: Bool = true
    ) {
        self.detector = detector
        self.allowedKinds = allowedKinds
        self.appliesGuardrail = appliesGuardrail

        /**
         Correcting someone's own writing is a transformation, not generation.
         The default guardrails occasionally refuse ordinary text on that basis;
         these are meant for exactly this kind of work.
         */
        model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }

    func corrections(for text: String) async throws -> [TextEdit] {
        guard model.isAvailable else { throw CorrectorError.modelUnavailable }

        let protected = ProtectedSpans.find(in: text)
        var edits: [TextEdit] = []

        for chunk in TextChunker.chunks(of: text) {
            /** The user can give up mid-pass, and a long field is several chunks. */
            try Task.checkCancellation()

            let source = String(text[chunk])
            guard isWorthCorrecting(source) else { continue }

            let language = detector.detect(source)

            guard let corrected = await corrected(source, language: language) else { continue }

            /**
             The language check catches the one failure the difference-based
             guardrail cannot: a fluent translation, where every word changes
             legitimately as far as spelling is concerned.
             */
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
                Log.app.info("Dropped a chunk the model rewrote rather than corrected")
                continue
            }

            edits += verdict.accepted
        }

        Log.app.info("Found \(edits.count, privacy: .public) edits")
        return edits
    }

    /** Nil when the model declines or fails, which leaves the chunk untouched. */
    private func corrected(_ text: String, language: CorrectionLanguage) async -> String? {
        if let result = await respond(to: text, using: language.instructions, asking: language.prompt(for: text)) {
            return result
        }

        /**
         The model's safety filter turns down ordinary text now and again, and
         it does so consistently for a given wording, so repeating the same
         request is pointless. Asking again in English gets an answer often
         enough to be worth the second round trip, and the text stays in its own
         language because the prompt still says which one it is.
         */
        guard language != .english else { return nil }

        Log.app.info("Retrying a declined chunk with English instructions")
        return await respond(
            to: text,
            using: CorrectionLanguage.english.instructions,
            asking: "Correct this \(language.displayName) text, keeping every word:\n\n\(text)"
        )
    }

    private func respond(to text: String, using instructions: String, asking prompt: String) async -> String? {
        let session = LanguageModelSession(model: model, instructions: instructions)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: CorrectedText.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content.text
        } catch {
            Log.app.info("Model declined a chunk: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /** Skips anything with no words in it, such as a line holding only a link. */
    private func isWorthCorrecting(_ text: String) -> Bool {
        text.contains { $0.isLetter }
    }

    /**
     Moves an edit's range from the chunk it was found in to the full text.

     Both strings hold the same characters over that span, so counting from the
     chunk's start gives the same position in either.
     */
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

/** The shape the model is asked to fill in, which keeps preamble out of the reply. */
@Generable
private struct CorrectedText {
    @Guide(
        description: """
        The text with only spelling, punctuation, capitalisation and spacing \
        corrected. Every original word must still be present, in the same order.
        """
    )
    let text: String
}

enum CorrectorError: Error {
    case modelUnavailable
}
