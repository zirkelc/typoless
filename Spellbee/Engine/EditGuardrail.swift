import Foundation

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
        in text: String,
        allowing rules: Set<CorrectionRule> = Set(CorrectionRule.allCases),
        protectedBy protected: [Range<String.Index>] = []
    ) -> Verdict {
        var accepted: [TextEdit] = []
        var rejected = 0

        for edit in edits {
            guard let rule = classify(edit, in: text) else {
                Log.app.info("Rejected an edit that was not a correction")
                rejected += 1
                continue
            }

            /**
             Skipped rather than rejected, here and below.

             `rejectedCount` measures how far the model strayed, which is what
             decides whether the chunk can be trusted at all. A change the user
             has simply asked us not to make says nothing about the model, so
             counting it would make a well-behaved model look like a rewriting
             one and throw away its other corrections.
             */
            guard rules.contains(rule) else { continue }

            guard !protected.contains(where: { $0.overlaps(edit.range) }) else {
                Log.app.info("Rejected a \(rule.rawValue, privacy: .public) edit inside protected text")
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
    static func classify(_ edit: TextEdit, in text: String) -> CorrectionRule? {
        let original = edit.original
        let replacement = edit.replacement

        guard original != replacement else { return nil }

        /** Same characters once spacing is ignored: only the spacing moved. */
        if withoutWhitespace(original) == withoutWhitespace(replacement) {
            return .spacing
        }

        let strippedOriginal = withoutPunctuation(withoutWhitespace(original))
        let strippedReplacement = withoutPunctuation(withoutWhitespace(replacement))

        /** Same letters and case once punctuation is ignored. */
        if strippedOriginal == strippedReplacement {
            return punctuationRule(for: edit, in: text)
        }

        /**
         Same letters, different case. Which capital it is depends on where it
         sits: the first word of a sentence is one question and a noun in the
         middle of a German sentence is a different one, and someone may well
         want the first and not the second.
         */
        if strippedOriginal.lowercased() == strippedReplacement.lowercased() {
            return startsASentence(edit, in: text) ? .capitalisation : .nounCapitalisation
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
            return .umlauts
        }

        return isSpellingFix(from: original, to: replacement) ? .typos : nil
    }

    /**
     Which punctuation question this edit is, once it is known to be one.

     Named by the marks that actually moved rather than by the marks present, so
     adding a comma to a sentence that already ends in a full stop is still a
     comma question.
     */
    private static func punctuationRule(for edit: TextEdit, in text: String) -> CorrectionRule {
        if addsSentenceFinalPunctuation(edit, in: text) { return .sentenceEndings }

        let changed = changedPunctuation(from: edit.original, to: edit.replacement)

        if !changed.isEmpty, changed.isSubset(of: apostrophes) { return .apostrophes }
        if !changed.isEmpty, changed.isSubset(of: [","]) { return .commas }

        return .otherPunctuation
    }

    /**
     Every mark whose count differs between the two, in either direction.

     A count rather than a set membership, so replacing `?!` with `?` is seen as
     a change to `!` even though both sides still contain a `?`.
     */
    private static func changedPunctuation(from original: String, to replacement: String) -> Set<Character> {
        var counts: [Character: Int] = [:]

        for character in original where character.isPunctuation || character.isSymbol {
            counts[character, default: 0] += 1
        }
        for character in replacement where character.isPunctuation || character.isSymbol {
            counts[character, default: 0] -= 1
        }

        return Set(counts.filter { $0.value != 0 }.keys)
    }

    /** Straight and curly, since a keyboard produces one and a model returns the other. */
    private static let apostrophes: Set<Character> = ["'", "\u{2019}", "\u{02BC}"]

    /**
     Whether this edit is at the start of a sentence.

     Judged from what precedes it in the text rather than from the edit alone,
     because the same word is a sentence opening in one place and an ordinary
     noun in another.
     */
    static func startsASentence(_ edit: TextEdit, in text: String) -> Bool {
        let before = text[..<edit.range.lowerBound].reversed().drop(while: \.isWhitespace)

        guard let previous = before.first else { return true }

        return sentenceFinalMarks.contains(previous)
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
             A typo stays in the alphabet the word was written in. A model that
             has come off the rails does not: `Danke` came back as `Danke퀎4`,
             which is two edits away and passes every other test here. Nothing a
             correction legitimately does introduces a letter from another
             script.
             */
            guard scripts(of: after).isSubset(of: scripts(of: before)) else { return false }

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

    /** Marks that close a sentence, and nothing else. */
    private static let sentenceFinalMarks: Set<Character> = [".", "!", "?", "…"]

    /**
     Whether this edit only puts a closing mark on the end of the text.

     Finishing a sentence is a correction in an email and a change of tone in a
     chat message, which is why it is the one kind of change with a setting of
     its own. It has to be recognised by position as well as by content: a full
     stop added mid-paragraph is ordinary punctuation, and only the one hanging
     off the end of what the user wrote is in question.
     */
    static func addsSentenceFinalPunctuation(_ edit: TextEdit, in text: String) -> Bool {
        /** Anything but spacing after this edit means it is not the end. */
        guard text[edit.range.upperBound...].allSatisfy(\.isWhitespace) else { return false }

        var stripped = Substring(edit.replacement)
        while let last = stripped.last, sentenceFinalMarks.contains(last) {
            stripped = stripped.dropLast()
        }

        return stripped.count < edit.replacement.count && stripped == edit.original
    }

    /** Coarse alphabet families, enough to tell a typo from a different writing system. */
    private enum Script {
        case latin, greek, cyrillic, other
    }

    /**
     Which alphabets a word draws its letters from.

     Only letters are considered. Digits, punctuation and symbols are judged by
     the checks above this one, and folding them in here would refuse ordinary
     corrections around them.
     */
    private static func scripts(of text: some StringProtocol) -> Set<Script> {
        var found: Set<Script> = []

        for character in text where character.isLetter {
            guard let scalar = character.unicodeScalars.first else { continue }

            switch scalar.value {
            case 0..<0x0250, 0x1E00...0x1EFF:
                found.insert(.latin)
            case 0x0370...0x03FF:
                found.insert(.greek)
            case 0x0400...0x04FF:
                found.insert(.cyrillic)
            default:
                found.insert(.other)
            }
        }

        return found
    }

    private static func withoutWhitespace(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    /**
     Strips punctuation only, deliberately leaving symbols in place.

     Symbols used to be stripped alongside punctuation, which quietly made every
     symbol interchangeable with every other: `5 €` to `5 $` and `🎉` to `😀`
     both reduced to the same letters on each side and were waved through as
     punctuation changes. One of those is a money error and the other rewrites
     the tone of a message.

     The cost is that a genuine symbol substitution, `->` to `→`, is now refused
     rather than allowed. That is the right answer anyway: it is a rewrite, not
     a correction.
     */
    private static func withoutPunctuation(_ text: String) -> String {
        text.filter { !$0.isPunctuation }
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
