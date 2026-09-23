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
        /** Edits refused for sitting inside protected text, which is not straying. */
        var protectedCount = 0

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

    /**
     - Parameter language: Which dictionary tells a grammar fix from a typo.
       Without one, a changed word ending can only be judged as a typo.
     */
    static func filter(
        _ edits: [TextEdit],
        in text: String,
        allowing rules: Set<CorrectionRule> = Set(CorrectionRule.allCases),
        protectedBy protected: [Range<String.Index>] = [],
        language: CorrectionLanguage? = nil
    ) -> Verdict {
        var accepted: [TextEdit] = []
        var rejected = 0
        var protectedCount = 0

        var edits = edits
        if let cut = cuttingContinuation(from: edits, in: text) {
            Log.app.info("Cut off words the model added after the end of the text")
            edits = cut
            rejected += 1
        }

        for edit in edits {
            guard let kinds = classify(edit, in: text, language: language) else {
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
            guard rules.isSuperset(of: kinds) else {
                /**
                 A change is found one word at a time, so one of them can hold a
                 rule the user turned off and a rule they still want: `buero` to
                 `Büro,` is an umlaut, a capital and a comma at once. Refusing
                 the whole word threw the wanted fixes away with the unwanted
                 one, on a fifth to two fifths of the changes refused this way.

                 Each piece is judged on its own, with nothing counted against
                 the model, and a piece the rules still refuse is simply left
                 out. A change that cannot be cut arrives back whole and is
                 skipped as before.
                 */
                for part in TextDiff.splitting(edit, in: text) where part != edit {
                    guard
                        let partKinds = classify(part, in: text, language: language),
                        rules.isSuperset(of: partKinds),
                        !isProtected(part, by: protected)
                    else { continue }

                    accepted.append(part)
                }

                continue
            }

            /**
             Counted apart from `rejectedCount`, which measures how far the
             model strayed from correcting. A model that tidied a URL or
             lowercased a handle has not rewritten the user's prose, and letting
             those votes decide trustworthiness meant that two @names in one
             Slack line threw away the real typo fix alongside them.
             */
            guard !isProtected(edit, by: protected) else {
                Log.app.info("Rejected an edit inside protected text")
                protectedCount += 1
                continue
            }

            accepted.append(edit)
        }

        return Verdict(accepted: accepted, rejectedCount: rejected, protectedCount: protectedCount)
    }

    /**
     Whether an edit lands in text the model was told to leave alone.

     An insertion has an empty range, and `overlaps` is false for an empty range
     however it sits, so protection used to be blind to every insertion: a comma
     could be dropped into the middle of a URL or a code span and nothing would
     stop it. Containment has to be asked separately.
     */
    private static func isProtected(_ edit: TextEdit, by protected: [Range<String.Index>]) -> Bool {
        protected.contains { span in
            span.overlaps(edit.range)
                || (span.lowerBound < edit.range.lowerBound && edit.range.lowerBound < span.upperBound)
        }
    }

    /**
     The edits with anything the model wrote past the end of the text removed,
     or nil when it wrote nothing there.

     A text that stops mid-sentence invites a small model to carry on, and
     Apple's does so with the instructions the framework appends after the
     prompt. Words after the end are never a correction, but left in place
     they join the last word's change, or stand as an insertion of their own,
     and are refused together with the real fix beside them.

     The last change keeps as much of its replacement as it takes to spell as
     many letters as it replaced, to the end of that word. What follows is the
     continuation. A full stop, or a word split in two, has no letters beyond
     that point, so neither is taken for one.
     */
    static func cuttingContinuation(from edits: [TextEdit], in text: String) -> [TextEdit]? {
        guard let last = edits.last, last.range.upperBound == text.endIndex else { return nil }

        let needed = last.original.filter(isLetterOrNumber).count
        let replacement = last.replacement
        var cut = replacement.startIndex
        var letters = 0

        while cut < replacement.endIndex, letters < needed {
            if isLetterOrNumber(replacement[cut]) { letters += 1 }
            cut = replacement.index(after: cut)
        }

        /** To the end of the word the count stopped in, so a fix is never cut in half. */
        while cut < replacement.endIndex, !replacement[cut].isWhitespace {
            cut = replacement.index(after: cut)
        }

        guard replacement[cut...].contains(where: isLetterOrNumber) else { return nil }

        let kept = String(replacement[..<cut])
        var trimmed = Array(edits.dropLast())

        if kept != last.original, !(kept.isEmpty && last.original.isEmpty) {
            trimmed.append(TextEdit(range: last.range, original: last.original, replacement: kept))
        }

        return trimmed
    }

    /**
     Whether the model answered in capitals.

     Every word of a shouted reply is the same letters in another case, so
     each one passes as a capital on its own, and a whole message came back in
     capitals that way. It is only visible across the chunk, and only a reply
     with every word in capitals is refused: a line of acronyms ("API, SDK and
     CLI docs") puts most of its words into capitals and is still a fix.

     Words of one letter do not count, since "I" and "A" are capitals either
     way, and neither does protected text such as code, which the model leaves
     as it was. Two words in capitals are enough, but only where the user did
     not write them that way: text written in capitals may stay in capitals.
     */
    static func isShouting(_ reply: String, over source: String) -> Bool {
        let words = countedWords(in: reply)
        let shouted = words.filter(isInCapitals)

        guard words.count >= 2, shouted.count == words.count else { return false }

        return countedWords(in: source).filter(isInCapitals).count < shouted.count
    }

    /** Words of two letters or more, outside protected text. */
    private static func countedWords(in text: String) -> [Substring] {
        let protected = ProtectedSpans.find(in: text)
        var visible = ""
        var index = text.startIndex

        /** Built in one pass, since replacing one span would move every index after it. */
        while index < text.endIndex {
            if let span = protected.first(where: { $0.contains(index) }) {
                visible.append(" ")
                index = span.upperBound
            } else {
                visible.append(text[index])
                index = text.index(after: index)
            }
        }

        return visible.split(whereSeparator: \.isWhitespace).filter { $0.count(where: \.isLetter) >= 2 }
    }

    private static func isInCapitals(_ word: Substring) -> Bool {
        !word.contains(where: \.isLowercase)
    }

    private static func isLetterOrNumber(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /**
     Every question this edit raises, or nil if it is not a correction at all.

     A set rather than one label, which was the important thing to get right.
     The checks used to run least-invasive first and return the first one that
     explained the change, so an edit that restored an umlaut *and* added a
     comma was filed as "umlaut" and the user's answer on commas was never
     consulted. Each dimension is now judged on its own, with the ones below it
     normalised away, so `buero` to `Büro` reports both the umlaut and the
     capital and needs permission for both.
     */
    static func classify(
        _ edit: TextEdit,
        in text: String,
        language: CorrectionLanguage? = nil
    ) -> Set<CorrectionRule>? {
        let original = edit.original
        let replacement = edit.replacement

        guard original != replacement else { return nil }

        /**
         Nothing may bring in a mark that writing does not use. Unicode's idea
         of punctuation is far wider than writing's: `*`, `_`, `#`, backtick
         and the brackets are all punctuation to `isPunctuation`, so a model
         that wrapped the letters it had changed in Markdown bold turned
         `evals` into `**E**vals`, and every test below read that as a capital
         plus a punctuation change and waved it through. Markup is not a
         correction of what someone wrote, whichever category its characters
         happen to fall in.
         */
        guard changedPunctuation(from: original, to: replacement).isSubset(of: correctableMarks) else {
            Log.app.info("Rejected an edit that brought in a mark corrections do not use")
            return nil
        }

        guard !addsListMarker(edit, in: text) else {
            Log.app.info("Rejected an edit that opened a line with a list marker")
            return nil
        }

        /**
         A line break is not spacing, whatever Unicode says about it.

         Both are whitespace, so turning a space into a newline had the same
         letters on each side and was filed as a spacing fix and waved through.
         What it actually does is restructure the message: one model, asked to
         correct a chat line, returned `i will` then each of `take a look
         tomorrow` on a line of its own, and every one of those breaks counted
         as tidying the spacing. Where the lines fall is the writer's decision,
         not a spelling question.
         */
        guard original.count(where: \.isNewline) == replacement.count(where: \.isNewline) else {
            Log.app.info("Rejected an edit that added or removed a line break")
            return nil
        }

        var kinds: Set<CorrectionRule> = []

        let bareOriginal = withoutWhitespace(original)
        let bareReplacement = withoutWhitespace(replacement)

        /** Either only the spacing moved, or the spacing moved along with something else. */
        if bareOriginal == bareReplacement || onlyWhitespace(original) != onlyWhitespace(replacement) {
            kinds.insert(.spacing)
        }

        if onlyPunctuation(original) != onlyPunctuation(replacement) {
            guard !changesMeaning(edit, in: text) else { return nil }

            kinds.insert(punctuationRule(for: edit, in: text))
        }

        let strippedOriginal = withoutPunctuation(bareOriginal)
        let strippedReplacement = withoutPunctuation(bareReplacement)
        let foldedOriginal = foldingUmlauts(strippedOriginal, lowercased: false)
        let foldedReplacement = foldingUmlauts(strippedReplacement, lowercased: false)

        /**
         The same word written with and without its umlauts.

         Typing `ue` for `ü` is the most common shortcut in written German, and
         restoring it is squarely the job. By edit distance it looks expensive:
         `buero` to `Büro` costs three, because the capital, the umlaut and the
         dropped `e` all count separately, which put it over the threshold for a
         typo and got it thrown away. Since the expansion is lossless, folding
         it back settles the question exactly rather than by distance.
         */
        if strippedOriginal.lowercased() != strippedReplacement.lowercased(),
           foldedOriginal.lowercased() == foldedReplacement.lowercased() {
            /**
             One direction only. The rule exists to restore letters a keyboard
             makes awkward, `ue` to `ü` and `ss` to `ß`, and folding compares
             the two forms as equal, so it read the reverse as an umlaut fix
             too. A model handed a correctly written German sign-off returned
             `Viele Grüße` as `Viele grüsse`, and every test here agreed it was
             a correction. Taking a letter the user typed and spelling it the
             long way round is never one.
             */
            guard umlautCount(in: replacement) >= umlautCount(in: original) else {
                Log.app.info("Rejected an edit that spelled an umlaut away")
                return nil
            }

            kinds.insert(.umlauts)
        }

        /**
         Same letters, different case, judged with any umlaut folded away so a
         capital cannot hide behind one. Which capital it is depends on where it
         sits: the first word of a sentence is one question and a noun in the
         middle of a German sentence is a different one, and someone may well
         want the first and not the second.
         */
        if foldedOriginal != foldedReplacement,
           foldedOriginal.lowercased() == foldedReplacement.lowercased() {
            kinds.insert(startsASentence(edit, in: text) ? .capitalisation : .nounCapitalisation)
        }

        /**
         Anything still different is a change of letters, which has to look
         like a typo or like a word put into another form of itself.
         */
        if foldedOriginal.lowercased() != foldedReplacement.lowercased() {
            guard let letterKinds = letterChanges(from: original, to: replacement, language: language) else {
                return nil
            }

            kinds.formUnion(letterKinds)

            /**
             A typo fix may also change a capital, and then it is both.

             `teh` to `The` is one change to one word, so the capital used to
             ride along on the spelling fix and land even with capitalisation
             switched off. Someone who turns that off writes in lower case
             deliberately, and for them an unwanted capital is a worse outcome
             than a typo left alone, so the setting has to be asked.
             */
            if changesWordInitialCase(from: original, to: replacement) {
                kinds.insert(startsASentence(edit, in: text) ? .capitalisation : .nounCapitalisation)
            }
        }

        return kinds.isEmpty ? nil : kinds
    }

    /**
     Punctuation changes that alter meaning rather than tidy it.

     A mark between digits is arithmetic, not punctuation: `1,500` and `1.500`
     are different numbers under different conventions, and `10:30` is a time,
     so a German-tuned model "fixing the separators" silently multiplies a price
     by a thousand. And swapping one sentence-final mark for a different one
     turns a question into a statement, which is a change of meaning wearing
     punctuation's clothes. Trimming `?!` down to `?` is not that, so the test
     is disjointness rather than mere difference.
     */
    /**
     Whether any word starts with a different case in one than in the other.

     Word-initial only, which is where capitalisation rules live. The word
     counts already match, since this is only asked of a change that has passed
     the spelling test.
     */
    private static func changesWordInitialCase(from original: String, to replacement: String) -> Bool {
        let originalWords = original.split(whereSeparator: \.isWhitespace)
        let replacementWords = replacement.split(whereSeparator: \.isWhitespace)

        guard originalWords.count == replacementWords.count else { return false }

        return zip(originalWords, replacementWords).contains { before, after in
            guard let opening = before.first, let corrected = after.first else { return false }

            return opening.isUppercase != corrected.isUppercase
        }
    }

    /** Whether any mark in this text sits directly between two digits. */
    private static func separatesDigits(_ text: String) -> Bool {
        let characters = Array(text)

        guard characters.count > 2 else { return false }

        return characters.indices.dropFirst().dropLast().contains { index in
            characters[index].isPunctuation
                && characters[index - 1].isNumber
                && characters[index + 1].isNumber
        }
    }

    private static func changesMeaning(_ edit: TextEdit, in text: String) -> Bool {
        /**
         Framed with one character of context, because the diff may hand over
         either the bare mark or the whole word around it, and a separator is
         only recognisable from its neighbours.
         */
        let lead = text[..<edit.range.lowerBound].last.map(String.init) ?? ""
        let trail = text[edit.range.upperBound...].first.map(String.init) ?? ""

        if separatesDigits(lead + edit.original + trail) || separatesDigits(lead + edit.replacement + trail) {
            return true
        }

        let before = Set(edit.original.filter(sentenceFinalMarks.contains))
        let after = Set(edit.replacement.filter(sentenceFinalMarks.contains))

        return !before.isEmpty && !after.isEmpty && before.isDisjoint(with: after)
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
     Every mark a correction is allowed to put in or take out.

     A closed list rather than a test, because the tests all say yes too often.
     These are the marks that separate and end sentences, quote speech and join
     words, in the straight and curly forms a keyboard and a model each produce.
     Everything outside it is markup, arithmetic or decoration: the model may
     still echo one back untouched, since only a change of count is measured
     here, but it may not introduce one.
     */
    private static let correctableMarks: Set<Character> = [
        ".", ",", ";", ":", "!", "?", "\u{2026}",
        "'", "\u{2019}", "\u{02BC}", "\u{2018}",
        "\"", "\u{201C}", "\u{201D}", "\u{201E}", "\u{201A}", "\u{00AB}", "\u{00BB}",
        "-", "\u{2010}", "\u{2013}", "\u{2014}",
    ]

    /**
     Whether this edit is at the start of a sentence.

     Judged from what precedes it in the text rather than from the edit alone,
     because the same word is a sentence opening in one place and an ordinary
     noun in another.
     */
    static func startsASentence(_ edit: TextEdit, in text: String) -> Bool {
        let preceding = text[..<edit.range.lowerBound]
        let skipped = preceding.reversed().prefix(while: \.isWhitespace)

        /**
         A line break opens a sentence as surely as a full stop does. Skipping
         backwards over it meant the first word of every line was judged by the
         previous line, which in chat and email rarely ends in a mark, so those
         capitals were filed as noun capitals. English does not carry that rule,
         so the opening word of a line could never be capitalised at all.
         */
        if skipped.contains(where: \.isNewline) { return true }

        guard let previous = preceding.reversed().drop(while: \.isWhitespace).first else { return true }

        return sentenceFinalMarks.contains(previous)
    }

    /**
     Rewrites umlauts and eszett to their two-letter forms.

     Case is preserved on request, because folding and lowercasing at once hid
     a capital behind an umlaut: `buero` to `Büro` compared equal, so the edit
     was called an umlaut change and the capitalisation setting never saw it.
     */
    private static func foldingUmlauts(_ text: String, lowercased: Bool = true) -> String {
        var folded = lowercased ? text.lowercased() : text

        for (umlaut, expansion) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] {
            folded = folded.replacingOccurrences(of: umlaut, with: expansion, options: .caseInsensitive)
        }

        return folded
    }

    /**
     What kind of change each changed word is, or nil if any of them is not a
     correction.

     Every word stays in place and only letters within words change. Requiring
     the word count to match is what stops the model from quietly adding a
     clarifying word or dropping a redundant one.
     */
    private static func letterChanges(
        from original: String,
        to replacement: String,
        language: CorrectionLanguage?
    ) -> Set<CorrectionRule>? {
        let originalWords = original.split(whereSeparator: \.isWhitespace)
        let replacementWords = replacement.split(whereSeparator: \.isWhitespace)

        guard
            originalWords.count == replacementWords.count,
            !originalWords.isEmpty
        else {
            return nil
        }

        var kinds: Set<CorrectionRule> = []

        for (before, after) in zip(originalWords, replacementWords) where before != after {
            if let language, isGroupChange(from: String(before), to: String(after), in: language)
                || isWordForm(from: String(before), to: String(after), in: language) {
                kinds.insert(.grammar)
            } else if isSpellingFix(from: String(before), to: String(after), language: language) {
                kinds.insert(.typos)
            } else {
                return nil
            }
        }

        return kinds
    }

    /**
     A real word turned into another form of itself: "dem" to "des", "go" to
     "goes", "hat" to "haben".

     Only the ending may change. The two share at least their first two
     letters and at least half of the shorter word, and neither ending is
     longer than three letters, which covers inflection and not much else:
     "was" to "were" or "ist" to "sind" change the stem and stay refused.

     The word it starts from has to be in the dictionary, and so does the
     result. That is the whole difference from a typo at the end of a word,
     since "helo" to "hello" has exactly the same shape.
     */
    private static func isWordForm(from before: String, to after: String, in language: CorrectionLanguage) -> Bool {
        let base = String(withoutPunctuation(before))
        let form = String(withoutPunctuation(after))
        let lowerBase = Array(base.lowercased())
        let lowerForm = Array(form.lowercased())

        guard lowerBase != lowerForm, scripts(of: form).isSubset(of: scripts(of: base)) else {
            return false
        }

        let shared = zip(lowerBase, lowerForm).prefix { $0 == $1 }.count
        let shorter = min(lowerBase.count, lowerForm.count)

        guard
            shared >= 2,
            shared * 2 >= shorter,
            lowerBase.count - shared <= 3,
            lowerForm.count - shared <= 3
        else {
            return false
        }

        return WordList.contains(base, in: language) && WordList.contains(form, in: language)
    }

    /** Whether both words are forms in one of the language's grammar groups. */
    private static func isGroupChange(from before: String, to after: String, in language: CorrectionLanguage) -> Bool {
        let word = withoutPunctuation(before).lowercased()
        let form = withoutPunctuation(after).lowercased()

        guard word != form else { return false }

        return language.grammarGroups.contains { $0.contains(word) && $0.contains(form) }
    }

    /** A spelling fix to one word. */
    private static func isSpellingFix(from before: String, to after: String, language: CorrectionLanguage?) -> Bool {
        /**
         A typo rarely lands on the first letter, while a word swapped for a
         different one usually starts differently. Without this, "is" to
         "has" reads as a one-character spelling fix and quietly changes what
         the sentence says.

         Unless the word is not a word at all and the fix is. "ectual" has no
         meaning to change, so "actual" can only be a fix, and "hte" can only
         be "the". The length has to stay the same, a letter swapped or two
         traded: a tool name is not in the dictionary either, and removing a
         letter from the front of "pnpm" makes "npm", a different tool.

         Two letters traded at the start are a typo even between real words:
         "sue" to "use". The same shape turns "on" into "no", which is the
         model's call from context, and the same risk the guardrail already
         takes with "now" to "not". Only the swap, with nothing else changed.
         */
        guard let firstBefore = before.first?.lowercased(), let firstAfter = after.first?.lowercased() else {
            return false
        }

        if firstBefore != firstAfter, !swapsFirstTwoLetters(from: before, to: after) {
            let word = String(withoutPunctuation(before))
            let fix = String(withoutPunctuation(after))

            guard
                let language,
                word.count == fix.count,
                !WordList.contains(word, in: language),
                WordList.contains(fix, in: language)
            else {
                return false
            }
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

    /** Whether the only change is the first two letters trading places. */
    private static func swapsFirstTwoLetters(from before: String, to after: String) -> Bool {
        let original = Array(before.lowercased())
        let changed = Array(after.lowercased())

        guard original.count >= 2, original.count == changed.count, original[0] != original[1] else {
            return false
        }

        return original[0] == changed[1] && original[1] == changed[0] && original[2...] == changed[2...]
    }

    /**
     Whether this edit opens a line with a bullet.

     The dash has to stay in `correctableMarks`, since joining two words with
     one is an everyday fix, so a model that returned its answer as a list item
     walked straight past that guard and put a bullet on the front of the
     user's message. Position settles what the character cannot: prose does not
     begin a line with a dash and a space.
     */
    private static func addsListMarker(_ edit: TextEdit, in text: String) -> Bool {
        guard
            let opening = edit.replacement.first,
            listMarkers.contains(opening),
            edit.original.first != opening,
            edit.replacement.dropFirst().first?.isWhitespace == true
        else {
            return false
        }

        return text[..<edit.range.lowerBound].last.map(\.isNewline) ?? true
    }

    /** Characters a model reaches for when it answers in a list. */
    private static let listMarkers: Set<Character> = ["-", "*", "\u{2022}", "\u{2013}", "\u{2014}"]

    /** Letters German writes with a diacritic, which a correction may add but never remove. */
    private static let umlautCharacters: Set<Character> = [
        "\u{E4}", "\u{F6}", "\u{FC}", "\u{DF}", "\u{C4}", "\u{D6}", "\u{DC}", "\u{1E9E}",
    ]

    private static func umlautCount(in text: String) -> Int {
        text.count { umlautCharacters.contains($0) }
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
        /**
         Anything but spacing after this edit, on this line, means it is not the
         end. The line rather than the whole field: text is corrected line by
         line, and judging by the end of the field meant that on any message
         with more than one line every line but the last failed this test. The
         full stop then fell through to the catch-all punctuation rule, so the
         one setting the product offers for exactly this question did nothing
         wherever it mattered most.
         */
        let restOfLine = text[edit.range.upperBound...].prefix { !$0.isNewline }

        guard restOfLine.allSatisfy(\.isWhitespace) else { return false }

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

    /** Just the spacing, so a change to it can be spotted alongside other changes. */
    private static func onlyWhitespace(_ text: String) -> String {
        text.filter(\.isWhitespace)
    }

    /** Just the punctuation, judged the same way and by the same definition as below. */
    private static func onlyPunctuation(_ text: String) -> String {
        text.filter(\.isPunctuation)
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
