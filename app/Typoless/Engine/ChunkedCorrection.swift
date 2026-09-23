import Foundation

/**
 The correction pipeline both backends share.

 Everything between "here is a field of text" and "here are the edits to make"
 is the same whichever model answers: split into chunks, work out which language
 each is in, ask, check the reply did not become a rewrite, and rebase the
 result onto the original. Only the asking differs.

 It lived twice, once per backend, differing in one call and one log line. That
 is not a tidiness problem: a review found four separate defects in it, and each
 had to be fixed in both copies, one of which had already drifted. The shape
 that makes those bugs unrepresentable is a single loop with the model handed in.
 */
enum ChunkedCorrection {
    /**
     - Parameter answer: Asks the model about one chunk. Nil leaves that chunk
       exactly as the user wrote it, which is what every failure does.
     */
    static func run(
        over text: String,
        settings: AppSettings,
        detector: LanguageDetector,
        appliesGuardrail: Bool,
        /**
         Nil where a backend has no measured limits of its own. The values in
         `CorrectionDeadline` are taken from Apple's on-device model, and a
         downloaded model is a different distribution: it generates slower, and
         its first request of the session waits for gigabytes of weights to
         load, which would spend the whole budget before anything was asked.
         */
        deadline: CorrectionDeadline?,
        /**
         Inherited from whoever called, so the closure below stays on the
         caller's actor. Both backends are actors and their closures touch their
         own state, which a nonisolated helper could not accept.
         */
        isolation: isolated (any Actor)? = #isolation,
        answer: (String, CorrectionLanguage, Bool) async throws -> String?
    ) async throws -> [TextEdit] {
        let protected = ProtectedSpans.find(in: text)
        var edits: [TextEdit] = []

        for chunk in TextChunker.chunks(of: text) {
            /** The user can give up mid-pass, and a long field is several chunks. */
            try Task.checkCancellation()

            /**
             Whatever has landed so far is kept and the rest of the field is
             left as written. Stopping is better than the alternative it
             replaced, which was to keep asking while the user watched an
             overlay sit on their text.
             */
            guard deadline?.hasExpired() != true else {
                Log.app.info("Out of time, leaving the rest of the field alone")
                break
            }

            let source = String(text[chunk])

            /** Only the opening chunk may be told to capitalise an opening word. */
            let startsText = chunk.lowerBound == text.startIndex

            /**
             Hidden before the model sees them rather than only vetoed
             afterwards. A link in the sentence does not merely survive the
             pass, it costs the pass: the same German line was corrected in
             none of six attempts with the link present and in all six with it
             masked. Found against the chunk rather than sliced out of the
             whole field's spans, so no index has to be mapped between the two.
             */
            let masked = MaskedText.mask(source, protecting: ProtectedSpans.find(in: source))

            /** A chunk that was nothing but a link has nothing left to correct. */
            guard masked.text.contains(where: \.isLetter) else { continue }

            /** Not a language the user asked for, so it is left exactly as written. */
            guard let language = detector.detect(source) else {
                Log.app.info("Skipped a chunk in a language that is not enabled")
                continue
            }

            /**
             The masked text first, and the text as written only if the markers
             did not come back.

             No marker survives every model on every sentence: the best of the
             eight measured is deleted outright in about one reply in ten,
             usually where the marker is the last thing on the line. Abandoning
             the chunk there was tried and is much worse than it sounds, since
             it throws away corrections that used to land and cost seven points
             of exact match across the English set. Asking again without the
             markers costs one more call on those replies and can do no worse
             than the pass the app would have made anyway.
             */
            var corrected = try await answer(masked.text, language, startsText).flatMap(masked.restore)

            if corrected == nil, !masked.hidesNothing, deadline?.hasExpired() != true {
                Log.app.info("A marker did not survive, asking again without them")
                corrected = try await answer(source, language, startsText)
            }

            guard let corrected else { continue }

            /**
             The language check catches the one failure the difference-based
             guardrail cannot: a fluent translation, where every word changes
             legitimately as far as spelling is concerned.
             */
            if appliesGuardrail, detector.detect(corrected) != language {
                Log.app.info("Dropped a chunk whose language changed")
                continue
            }

            if appliesGuardrail, EditGuardrail.isShouting(corrected, over: source) {
                Log.app.info("Dropped a chunk the model returned in capitals")
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
                in: text,
                allowing: settings.rules(for: language),
                protectedBy: protected,
                language: language
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

    /**
     Moves an edit from the chunk's own coordinates into the whole field's.

     The chunk is handed to the model as a string of its own, so every offset
     comes back relative to that. Counting in characters rather than in UTF-16
     units, because both ends of this conversion are Swift strings.
     */
    private static func rebase(
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
