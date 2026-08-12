import Foundation

/** The only kinds of change this app is allowed to make. */
enum EditKind: String, CaseIterable {
    case whitespace
    case punctuation
    case casing
    case spelling
}

/**
 Decides which of the model's changes are allowed to happen.

 This is what actually enforces "correct, do not rewrite". Asking a model nicely
 does not hold: it will occasionally tighten a sentence, swap a word for a
 better one, or translate a phrase, and every one of those would be a surprise
 in a message the user is about to send. So each change is classified by
 comparing the two strings, and anything that is not spelling, punctuation,
 capitalisation or spacing is dropped.

 Nothing here consults the model or trusts anything it says about its own work.
 */
enum EditGuardrail {
    /**
     Largest single-word change treated as a spelling fix.

     Two edits covers the ordinary typo. Beyond that a word has usually become a
     different word, which is a rewrite.
     */
    private static let maximumSpellingDistance = 2

    /** What survived, and whether the changes as a whole looked like corrections. */
    struct Verdict {
        let accepted: [TextEdit]
        let rejectedCount: Int

        /**
         Whether the changes are worth applying at all.

         A pass that had to throw away more than it kept was not a correction of
         the user's writing, it was a rewrite with a few coincidences in it. The
         individual survivors of such a pass are not safe to keep: dropping all
         but one word of a translated sentence leaves a mixture of two languages,
         which is worse than the original and worse than doing nothing.
         */
        var isTrustworthy: Bool {
            rejectedCount <= accepted.count
        }
    }

    static func filter(
        _ edits: [TextEdit],
        allowing kinds: Set<EditKind> = Set(EditKind.allCases),
        protectedBy protected: [Range<String.Index>] = []
    ) -> Verdict {
        var accepted: [TextEdit] = []
        var rejected = 0

        for edit in edits {
            guard let kind = classify(edit) else {
                Log.app.info("Rejected an edit that was not a correction")
                rejected += 1
                continue
            }

            guard kinds.contains(kind) else { continue }

            guard !protected.contains(where: { $0.overlaps(edit.range) }) else {
                Log.app.info("Rejected a \(kind.rawValue, privacy: .public) edit inside protected text")
                rejected += 1
                continue
            }

            accepted.append(edit)
        }

        return Verdict(accepted: accepted, rejectedCount: rejected)
    }

    /**
     What kind of change this is, or nil if it is not one we permit.

     The order matters: the checks run from least invasive to most, so a change
     is described by the smallest thing that explains it.
     */
    static func classify(_ edit: TextEdit) -> EditKind? {
        let original = edit.original
        let replacement = edit.replacement

        guard original != replacement else { return nil }

        /** Same characters once spacing is ignored: only the spacing moved. */
        if withoutWhitespace(original) == withoutWhitespace(replacement) {
            return .whitespace
        }

        let strippedOriginal = withoutPunctuation(withoutWhitespace(original))
        let strippedReplacement = withoutPunctuation(withoutWhitespace(replacement))

        /** Same letters and case once punctuation is ignored. */
        if strippedOriginal == strippedReplacement {
            return .punctuation
        }

        /** Same letters, different case. */
        if strippedOriginal.lowercased() == strippedReplacement.lowercased() {
            return .casing
        }

        /**
         The same word written with and without its umlauts.

         Typing `ue` for `ü` is the most common shortcut in written German, and
         restoring it is squarely the job. By edit distance it looks expensive:
         `buero` to `Büro` costs three, because the capital, the umlaut and the
         dropped `e` all count separately, which put it over the threshold for a
         typo and got it thrown away. Since the expansion is lossless, folding
         it back settles the question exactly rather than by distance.
         */
        if foldingUmlauts(strippedOriginal) == foldingUmlauts(strippedReplacement) {
            return .spelling
        }

        return isSpellingFix(from: original, to: replacement) ? .spelling : nil
    }

    /** Rewrites umlauts and eszett to their two-letter forms, lowercased. */
    private static func foldingUmlauts(_ text: String) -> String {
        var folded = text.lowercased()

        for (umlaut, expansion) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] {
            folded = folded.replacingOccurrences(of: umlaut, with: expansion)
        }

        return folded
    }

    /**
     A spelling fix keeps every word in place and changes letters within them.

     Requiring the word count to match is what stops the model from quietly
     adding a clarifying word or dropping a redundant one.
     */
    private static func isSpellingFix(from original: String, to replacement: String) -> Bool {
        let originalWords = original.split(whereSeparator: \.isWhitespace)
        let replacementWords = replacement.split(whereSeparator: \.isWhitespace)

        guard
            originalWords.count == replacementWords.count,
            !originalWords.isEmpty
        else {
            return false
        }

        return zip(originalWords, replacementWords).allSatisfy { before, after in
            guard before != after else { return true }

            /**
             A typo rarely lands on the first letter, while a word swapped for a
             different one usually starts differently. Without this, "is" to
             "has" reads as a one-character spelling fix and quietly changes what
             the sentence says.
             */
            guard
                let firstBefore = before.first?.lowercased(),
                let firstAfter = after.first?.lowercased(),
                firstBefore == firstAfter
            else {
                return false
            }

            /**
             Measured without case, because case is not a spelling mistake and
             counting it as one refuses real fixes. `wendesday` to `wednesday`
             is two edits and allowed; the same fix written `Wednesday`, which
             is what a model returns at the start of a sentence, was three and
             refused. Nothing is loosened by ignoring case here: a change that
             is only case never reaches this point, since it is classified as
             capitalisation several checks earlier.
             */
            let lowercasedBefore = before.lowercased()
            let distance = editDistance(lowercasedBefore, after.lowercased())

            return distance <= maximumSpellingDistance && distance < lowercasedBefore.count
        }
    }

    private static func withoutWhitespace(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private static func withoutPunctuation(_ text: String) -> String {
        text.filter { !$0.isPunctuation && !$0.isSymbol }
    }

    /** Levenshtein distance, two rows at a time. */
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let source = Array(lhs)
        let target = Array(rhs)

        guard !source.isEmpty else { return target.count }
        guard !target.isEmpty else { return source.count }

        var previous = Array(0...target.count)
        var current = previous

        for i in 1...source.count {
            current[0] = i

            for j in 1...target.count {
                let substitution = previous[j - 1] + (source[i - 1] == target[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }

            previous = current
        }

        return previous[target.count]
    }
}
