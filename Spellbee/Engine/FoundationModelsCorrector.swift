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

    /**
     Whether the model's changes are judged before being applied.

     Turning this off applies whatever comes back, including a rephrased or
     translated sentence. It exists so the model can be evaluated on its own
     terms, which the guardrail otherwise obscures.
     */
    private let appliesGuardrail: Bool

    init(
        detector: LanguageDetector = LanguageDetector(),
        appliesGuardrail: Bool = true
    ) {
        self.detector = detector
        self.appliesGuardrail = appliesGuardrail

        /**
         Correcting someone's own writing is a transformation, not generation.
         The default guardrails occasionally refuse ordinary text on that basis;
         these are meant for exactly this kind of work.
         */
        model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }

    func corrections(for text: String, settings: AppSettings) async throws -> [TextEdit] {
        guard model.isAvailable else { throw CorrectorError.modelUnavailable }

        return try await ChunkedCorrection.run(
            over: text,
            settings: settings,
            detector: detector,
            appliesGuardrail: appliesGuardrail
        ) { source, language, startsText in
            guard self.isWorthCorrecting(source) else { return nil }

            return await self.corrected(source, language: language, startsText: startsText)
        }
    }

    /** Nil when the model declines or fails, which leaves the chunk untouched. */
    private func corrected(
        _ text: String,
        language: CorrectionLanguage,
        startsText: Bool
    ) async -> String? {
        if let result = await respond(
            to: text,
            using: language.instructions(startsText: startsText),
            asking: language.prompt(for: text)
        ) {
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
            using: CorrectionLanguage.english.instructions(startsText: startsText),
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
            /** An empty reply is a failure, not an instruction to delete the line. */
            guard response.content.text.contains(where: \.isLetter) else {
                Log.app.info("Model returned nothing usable")
                return nil
            }

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
}

/**
 The shape the model is asked to fill in, which keeps preamble out of the reply.

 The description is read by the model, so it is part of the prompt whether or
 not it is written like one, and it is worth as much as a prompt change:
 removing it entirely costs 16 cases of 168.

 It used to carry a second sentence, requiring every original word to still be
 present in the same order. Measured on its own that sentence scores 94 against
 92 for no description at all, and adding it to the sentence below takes 113
 down to 108. It is not redundant with the wording, it is worse than nothing,
 which is the same finding the prompt sweep produced: this model does worse at a
 rule the more other words surround it.
 */
@Generable
private struct CorrectedText {
    @Guide(
        description: """
        The text with only spelling, punctuation, capitalisation and spacing \
        corrected.
        """
    )
    let text: String
}

enum CorrectorError: Error {
    case modelUnavailable
}
