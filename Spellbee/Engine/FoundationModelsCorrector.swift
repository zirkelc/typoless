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

        /** One budget for the whole pass, shared by every chunk and every retry. */
        let deadline = CorrectionDeadline()

        return try await ChunkedCorrection.run(
            over: text,
            settings: settings,
            detector: detector,
            appliesGuardrail: appliesGuardrail,
            deadline: deadline
        ) { source, language, startsText in
            guard self.isWorthCorrecting(source) else { return nil }

            return await self.corrected(
                source,
                language: language,
                startsText: startsText,
                deadline: deadline
            )
        }
    }

    /** Nil when the model declines or fails, which leaves the chunk untouched. */
    private func corrected(
        _ text: String,
        language: CorrectionLanguage,
        startsText: Bool,
        deadline: CorrectionDeadline
    ) async -> String? {
        if let result = await respond(
            to: text,
            using: language.instructions(startsText: startsText),
            asking: language.prompt(for: text),
            within: deadline.allowance()
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
        guard language != .english, !deadline.hasExpired() else { return nil }

        Log.app.info("Retrying a declined chunk with English instructions")
        return await respond(
            to: text,
            using: CorrectionLanguage.english.instructions(startsText: startsText),
            asking: "Correct this \(language.displayName) text, keeping every word:\n\n\(text)",
            within: deadline.allowance()
        )
    }

    private func respond(
        to text: String,
        using instructions: String,
        asking prompt: String,
        within allowance: Duration
    ) async -> String? {
        let model = model

        let reply = await answered(within: allowance) {
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

        guard let reply else { return nil }

        /** An empty reply is a failure, not an instruction to delete the line. */
        guard reply.contains(where: \.isLetter) else {
            Log.app.info("Model returned nothing usable")
            return nil
        }

        return reply
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
 not it is written like one. Removing it entirely costs 4 cases of 168, 112
 against 108.

 It used to carry a second sentence, requiring every original word to still be
 present in the same order. That sentence alone scores 99 against 108 for no
 description at all, so it is not merely redundant, it is nine cases worse than
 silence. Removing it from the sentence below is worth **3 cases of 168**, 109
 to 112, measured twice. It is not redundant with the wording, it is
 worse than nothing, which is the same finding the prompt sweep produced: this
 model does worse at a rule the more other words surround it.

 Every figure above is measured with the type name held still, which took two
 attempts. **The name of the type is part of what the model reads**: holding the
 description identical and changing only the name moves 15 to 21 replies of 168.
 A failing case made it plain by echoing its own schema back, `name:
 CorrectedText, schema: {...}`. Nothing here is more than a shape to fill in, so
 nothing warned that renaming it was an experiment, and the first sweep of these
 wordings gave each one a name of its own and so measured both at once. It
 reported this gain as 5 rather than 3, and the cost of dropping the description
 as 16 rather than 4.

 Declaring the shape inside another type is transparent, 0 of 168 replies
 changed, which is what makes a description sweep possible without renaming
 anything.

 The name itself is worth a sweep of its own. Six of them span 110 to 114, and
 the neutral `Text` is the worst of them, so a name that says something about the
 task is doing work. Not acted on: 4 cases across six arms chosen on the same
 168 they are reported on is how a winner gets manufactured.
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
