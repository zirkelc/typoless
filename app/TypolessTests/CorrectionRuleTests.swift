import Testing
@testable import Typoless

/**
 Every rule is told apart.

 The classifier names which question a change is, not just that it is a
 punctuation one, because "add a comma" and "add a full stop" are not the same
 decision and people want to answer them differently.
 */
struct EveryRuleToldApartTests {
    static let cases: Array<RuleCase> = [
        RuleCase("spacing", "hello  world", "hello world", expect: [.spacing]),
        RuleCase("sentence capital", "hello there", "Hello there", expect: [.capitalisation]),
        RuleCase("capital after a full stop", "done. whats next", "done. Whats next", expect: [.capitalisation]),
        RuleCase("noun capital mid-sentence", "ein test", "ein Test", expect: [.nounCapitalisation]),
        RuleCase("comma", "well done everyone", "well done, everyone", expect: [.commas]),
        RuleCase("apostrophe", "its ready", "it's ready", expect: [.apostrophes]),
        RuleCase("curly apostrophe", "its ready", "it\u{2019}s ready", expect: [.apostrophes]),
        RuleCase("full stop at the end", "see you tomorrow", "see you tomorrow.", expect: [.sentenceEndings]),
        RuleCase("other punctuation", "really?!", "really?", expect: [.otherPunctuation]),
        RuleCase("umlaut", "gruesse", "grüße", expect: [.umlauts]),
        RuleCase("typo", "teh meeting", "the meeting", expect: [.typos]),
        RuleCase("not a correction", "the meeting", "the appointment", expect: []),
        RuleCase("a verb put into its form", "she go home", "she goes home", in: .english, expect: [.grammar]),
        RuleCase("an article put into its case", "wegen dem", "wegen des", in: .german, expect: [.grammar]),
        /** "Termin" is a German word, so the ending is grammar, and its capital is still asked about. */
        RuleCase("a noun put into its case", "wegen des termin", "wegen des Termins", in: .german, expect: [.grammar, .nounCapitalisation]),
        RuleCase("a verb longer than a typo allows", "wir hat zeit", "wir haben zeit", in: .german, expect: [.grammar]),
        /** "helo" is not a word, so the same shape is a typo. */
        RuleCase("a typo at the end of a word", "helo world", "hello world", in: .english, expect: [.typos]),
        /** The stem changes, which is beyond an ending. */
        RuleCase("an irregular form is not an ending", "they was late", "they were late", in: .english, expect: []),
        /** Without a dictionary a changed ending can only be judged as a typo. */
        RuleCase("no language, no grammar", "wegen dem", "wegen des", expect: [.typos]),
    ]

    @Test(arguments: cases)
    func `the edit names its rule`(_ row: RuleCase) {
        // Arrange
        let expected = row.expected

        // Act
        let rules = Guardrail.rules(row.original, row.corrected, in: row.language)

        // Assert
        #expect(rules == expected)
    }
}

/** A language turns off the rules it does not want. */
struct LanguageTurnsOffRulesTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase(
            "commas off",
            "well done everyone",
            "Well done, everyone",
            allowing: [.capitalisation, .typos],
            expect: "Well done everyone"
        ),
        GuardrailCase(
            "noun capitals off, sentence capitals on",
            "hallo, das ist ein test",
            "Hallo, das ist ein Test",
            allowing: [.capitalisation],
            expect: "Hallo, das ist ein test"
        ),
        GuardrailCase(
            "umlauts off does not stop typos",
            "gruesse aus muenchen",
            "grüße aus münchen",
            allowing: [.typos],
            expect: "gruesse aus muenchen"
        ),
        GuardrailCase(
            "sentence endings off",
            "see you tomorrow",
            "See you tomorrow.",
            allowing: [.capitalisation, .typos, .commas],
            expect: "See you tomorrow"
        ),
        GuardrailCase(
            "sentence endings on",
            "see you tomorrow",
            "See you tomorrow.",
            allowing: [.capitalisation, .sentenceEndings],
            expect: "See you tomorrow."
        ),
        GuardrailCase(
            "declining a rule does not poison the chunk",
            "hi anna, teh deploy ist durch",
            "Hi Anna, the deploy ist durch",
            allowing: [.capitalisation, .nounCapitalisation],
            expect: "Hi Anna, teh deploy ist durch"
        ),
        /**
         A name in the middle of a sentence is a noun capital as far as this can tell,
         because position is the only evidence it has: nothing here knows "Anna" is a
         person and "test" is not. So turning noun capitals off in German also stops
         proper nouns being capitalised mid-sentence. Pinned rather than hidden.
         */
        GuardrailCase(
            "a name mid-sentence counts as a noun capital",
            "hi anna",
            "Hi Anna",
            allowing: [.capitalisation],
            expect: "Hi anna"
        ),
    ]

    @Test(arguments: cases)
    func `only the permitted rules land`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/**
 A full stop is judged by the end of its line.

 Corrections run line by line, so judging "is this the end of a sentence" by the
 end of the whole field meant that on any message with more than one line every
 line but the last failed the test. The full stop then fell through to the
 catch-all punctuation rule, and the setting offered for exactly this question
 did nothing wherever it mattered.
 */
struct FullStopByLineEndTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase(
            "a stop on a middle line, endings off",
            "hallo anna\nwie gehts",
            "hallo anna.\nwie gehts",
            allowing: [.capitalisation, .typos, .commas],
            expect: "hallo anna\nwie gehts"
        ),
        GuardrailCase(
            "a stop on the last line, endings off",
            "hallo anna\nwie gehts",
            "hallo anna\nwie gehts.",
            allowing: [.capitalisation, .typos, .commas],
            expect: "hallo anna\nwie gehts"
        ),
        GuardrailCase(
            "a stop on a middle line, endings on",
            "hallo anna\nwie gehts",
            "hallo anna.\nwie gehts",
            allowing: [.capitalisation, .sentenceEndings],
            expect: "hallo anna.\nwie gehts"
        ),
        GuardrailCase(
            "a stop genuinely mid-line is ordinary punctuation",
            "hallo anna wie gehts",
            "hallo. anna wie gehts",
            allowing: [.capitalisation, .typos, .otherPunctuation],
            expect: "hallo. anna wie gehts"
        ),
    ]

    @Test(arguments: cases)
    func `the stop follows the sentence endings rule`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/**
 An edit that does two things needs permission for both.

 An edit can raise more than one question at once, and every one of them has to
 be permitted before it is applied. Restoring an umlaut while also adding a comma
 used to report only the umlaut, so the comma setting was never asked.
 */
struct EditNeedsEveryPermissionTests {
    static let ruleCases: Array<RuleCase> = [
        RuleCase("umlaut and a noun capital", "das ist mein buero", "das ist mein Büro", expect: [.umlauts, .nounCapitalisation]),
        RuleCase("umlaut and a comma", "gruesse dich", "grüße, dich", expect: [.umlauts, .commas]),
        RuleCase("umlaut and a joined word", "haus tuer", "Haustür", expect: [.umlauts, .spacing, .capitalisation]),
        RuleCase("umlaut alone", "gruesse", "grüße", expect: [.umlauts]),
    ]

    static let cases: Array<GuardrailCase> = [
        GuardrailCase(
            "an umlaut may not smuggle in a capital",
            "das ist mein buero",
            "das ist mein Büro",
            allowing: [.umlauts, .typos, .spacing],
            expect: "das ist mein buero"
        ),
        GuardrailCase(
            "an umlaut may not smuggle in a comma",
            "gruesse dich",
            "grüße, dich",
            allowing: [.umlauts, .typos, .spacing],
            expect: "gruesse dich"
        ),
        GuardrailCase(
            "with both allowed it lands",
            "das ist mein buero",
            "das ist mein Büro",
            allowing: [.umlauts, .nounCapitalisation],
            expect: "das ist mein Büro"
        ),
    ]

    @Test(arguments: ruleCases)
    func `the edit names every rule it raises`(_ row: RuleCase) {
        // Arrange
        let expected = row.expected

        // Act
        let rules = Guardrail.rules(row.original, row.corrected)

        // Assert
        #expect(rules == expected)
    }

    @Test(arguments: cases)
    func `the edit lands only when every rule is permitted`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/** A line break opens a sentence. */
struct LineBreakOpensSentenceTests {
    @Test func `first word of a new line`() {
        // Arrange
        let original = "hi anna\nhope you are well"
        let corrected = "hi anna\nHope you are well"

        // Act
        let rules = Guardrail.rules(original, corrected)

        // Assert
        #expect(rules == [.capitalisation])
    }

    @Test func `english capitalises after a line break`() {
        // Arrange
        let original = "hi anna\nhope you are well"
        let output = "Hi anna\nHope you are well"

        // Act
        let result = Guardrail.corrected(original, output, allowing: [.capitalisation, .typos])

        // Assert
        #expect(result == "Hi anna\nHope you are well")
    }
}

/**
 English capitalises names.

 English does not capitalise nouns as a class, so the rule was left out. But the
 classifier judges a capital by position, not by knowing the word, so every
 mid-sentence capital lands under it and names could never be fixed.
 */
struct EnglishCapitalisesNamesTests {
    static let englishRules: Set<CorrectionRule> = [
        .spacing, .capitalisation, .nounCapitalisation,
        .commas, .sentenceEndings, .otherPunctuation,
        .apostrophes, .typos,
    ]

    static let cases: Array<GuardrailCase> = [
        GuardrailCase("a name mid-sentence", "i work at google", "I work at Google", allowing: englishRules, expect: "I work at Google"),
        GuardrailCase("a weekday", "see you on tuesday", "See you on Tuesday", allowing: englishRules, expect: "See you on Tuesday"),
        GuardrailCase(
            "still refused when the rule is off",
            "i work at google",
            "I work at Google",
            allowing: englishRules.subtracting([.nounCapitalisation]),
            expect: "I work at google"
        ),
        GuardrailCase(
            "it is still not a licence to rewrite",
            "i work at google",
            "I work at Alphabet",
            allowing: englishRules,
            expect: "I work at google"
        ),
    ]

    @Test(arguments: cases)
    func `a name is capitalised under the noun rule`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/** A typo fix that also changes a capital needs both. */
struct TypoWithCapitalNeedsBothTests {
    static let ruleCases: Array<RuleCase> = [
        RuleCase("typo carrying a sentence capital", "teh cat sat", "The cat sat", expect: [.typos, .capitalisation]),
        RuleCase("typo carrying a mid-sentence capital", "i met teh anna", "i met Teh anna", expect: [.nounCapitalisation]),
        RuleCase("typo with no capital in it", "teh cat sat", "the cat sat", expect: [.typos]),
    ]

    static let cases: Array<GuardrailCase> = [
        GuardrailCase(
            "capitalisation off refuses the capital and the fix with it",
            "teh cat sat",
            "The cat sat",
            allowing: [.typos, .spacing, .commas],
            expect: "teh cat sat"
        ),
        GuardrailCase(
            "with both allowed it lands",
            "teh cat sat",
            "The cat sat",
            allowing: [.typos, .capitalisation],
            expect: "The cat sat"
        ),
        GuardrailCase(
            "a lower-case typo fix is untouched by this",
            "teh cat sat",
            "the cat sat",
            allowing: [.typos],
            expect: "the cat sat"
        ),
    ]

    @Test(arguments: ruleCases)
    func `the edit names every rule it raises`(_ row: RuleCase) {
        // Arrange
        let expected = row.expected

        // Act
        let rules = Guardrail.rules(row.original, row.corrected)

        // Assert
        #expect(rules == expected)
    }

    @Test(arguments: cases)
    func `the fix lands only when both are permitted`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}
