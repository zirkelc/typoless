import Testing
@testable import Typoless

/**
 Symbols are content, not punctuation.

 Stripping symbols alongside punctuation made every symbol interchangeable with
 every other, so a money amount and the tone of a message were both one
 unremarkable "punctuation change" away from being rewritten.
 */
struct SymbolsAreContentTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase("emoji swap", "We shipped it 🎉", "We shipped it 😀", expect: "We shipped it 🎉"),
        GuardrailCase("currency swap", "Kosten: 5 € netto", "Kosten: 5 $ netto", expect: "Kosten: 5 € netto"),
        GuardrailCase(
            "corrections around an emoji still land",
            "i think its ready 🎉",
            "I think it's ready 🎉",
            expect: "I think it's ready 🎉"
        ),
        GuardrailCase(
            "corrections around a currency still land",
            "das kostet 5 € netto",
            "Das kostet 5 € netto",
            expect: "Das kostet 5 € netto"
        ),
    ]

    @Test(arguments: cases)
    func `a symbol is never swapped`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/** A typo stays in its own alphabet. */
struct TypoStaysInAlphabetTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase("junk appended", "Danke", "Danke\u{D00E}4", expect: "Danke"),
        GuardrailCase(
            "latin accents are not another alphabet",
            "gruesse aus muenchen",
            "Grüße aus München",
            expect: "Grüße aus München"
        ),
    ]

    @Test(arguments: cases)
    func `a fix does not change the alphabet`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/** Punctuation that changes meaning is not punctuation. */
struct MeaningfulPunctuationTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase("a thousands separator", "Das kostet 1,500 Euro", "Das kostet 1.500 Euro", expect: "Das kostet 1,500 Euro"),
        GuardrailCase("the other way round", "Das kostet 1.500 Euro", "Das kostet 1,500 Euro", expect: "Das kostet 1.500 Euro"),
        GuardrailCase("a time", "we meet at 10:30 sharp", "we meet at 10.30 sharp", expect: "we meet at 10:30 sharp"),
        GuardrailCase("a question turned into a statement", "kommst du morgen?", "kommst du morgen.", expect: "kommst du morgen?"),
        GuardrailCase("trimming a doubled mark is still allowed", "really?!", "really?", expect: "really?"),
        GuardrailCase("a comma next to a word is untouched by this", "hello , world", "hello, world", expect: "hello, world"),
    ]

    @Test(arguments: cases)
    func `the meaning is kept`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/** Markup is not punctuation. */
struct MarkupIsNotPunctuationTests {
    static let cases: Array<GuardrailCase> = [
        /**
         A model that shows its work by bolding what it changed. Seen in Slack: a
         German line came back with every changed letter wrapped in `**`, and since
         `*` is punctuation to Unicode, each one read as a capital plus a
         punctuation change and all four landed in the user's message.
         */
        GuardrailCase(
            "markdown bold around a changed letter",
            "hab die evals gefixt",
            "Hab die **E**vals **G**efixt",
            expect: "hab die evals gefixt"
        ),
        GuardrailCase("markdown bold around a whole word", "das war gut", "das war **gut**", expect: "das war gut"),
        GuardrailCase("backticks the user did not write", "run the script", "run the `script`", expect: "run the script"),
        GuardrailCase("italics", "that was fast", "that was _fast_", expect: "that was fast"),
        GuardrailCase("a heading marker", "next steps", "## next steps", expect: "next steps"),
        GuardrailCase("a bullet the model added", "buy milk", "- buy milk", expect: "buy milk"),
        GuardrailCase(
            "bolding a word blocks that word and nothing else",
            "teh cat sat",
            "**The** cat sat.",
            expect: "teh cat sat."
        ),
        /**
         The marks writing actually uses still work, in both forms, and a mark the
         user wrote themselves may still be moved around.
         */
        GuardrailCase("curly quotes still land", "he said hi", "he said \u{201C}hi\u{201D}", expect: "he said \u{201C}hi\u{201D}"),
        GuardrailCase(
            "german quotes still land",
            "er sagte hallo",
            "er sagte \u{201E}hallo\u{201C}",
            expect: "er sagte \u{201E}hallo\u{201C}"
        ),
        GuardrailCase("an em dash still lands", "wait what", "wait \u{2014} what", expect: "wait \u{2014} what"),
        GuardrailCase("a hyphen still lands", "well known issue", "well-known issue", expect: "well-known issue"),
        GuardrailCase("an ellipsis still lands", "i wondered", "i wondered\u{2026}", expect: "i wondered\u{2026}"),
        GuardrailCase(
            "an asterisk the user wrote survives being moved past",
            "*note* this ,here",
            "*note* this, here",
            expect: "*note* this, here"
        ),
    ]

    @Test(arguments: cases)
    func `markup the user did not write never lands`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }

    @Test func `bolding is not a correction`() {
        // Arrange
        let original = "evals"
        let corrected = "**E**vals"

        // Act
        let rules = Guardrail.rules(original, corrected)

        // Assert
        #expect(rules == [])
    }
}

/** A line break is not spacing. */
struct LineBreakIsNotSpacingTests {
    static let cases: Array<GuardrailCase> = [
        /**
         Seen from a model asked to correct a chat message: it returned the tail of
         the line one word per line, and every break passed as a spacing fix.
         */
        GuardrailCase(
            "a word pushed onto its own line",
            "i will take a look tomorrow",
            "i will\ntake\na\nlook\ntomorrow",
            expect: "i will take a look tomorrow"
        ),
        GuardrailCase(
            "a line break inserted before a link",
            "see this github.com/a/b",
            "see this\ngithub.com/a/b",
            expect: "see this github.com/a/b"
        ),
        GuardrailCase(
            "two lines joined into one",
            "first line\nsecond line",
            "first line second line",
            expect: "first line\nsecond line"
        ),
        GuardrailCase("a double space still collapses", "hello  world", "hello world", expect: "hello world"),
        GuardrailCase("a space before a comma still goes", "a , b", "a, b", expect: "a, b"),
        GuardrailCase(
            "a line break the model left alone is no obstacle",
            "hallo anna\n\nvielen dank",
            "Hallo Anna\n\nVielen Dank",
            allowing: Set(CorrectionRule.allCases),
            expect: "Hallo Anna\n\nVielen Dank"
        ),
    ]

    @Test(arguments: cases)
    func `line breaks are kept as written`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/**
 Umlauts are restored, never spelled away.

 Seen from the model on a correctly written German sign-off: it returned the
 eszett spelled out and the noun lowercased, and folding made the two compare
 equal so it passed as a fix.
 */
struct UmlautsRestoredTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase(
            "an eszett is not spelled back out",
            "Viele Gr\u{FC}\u{DF}e",
            "Viele gr\u{FC}sse",
            expect: "Viele Gr\u{FC}\u{DF}e"
        ),
        GuardrailCase("an umlaut is not spelled back out", "die \u{C4}nderungen", "die Aenderungen", expect: "die \u{C4}nderungen"),
        GuardrailCase(
            "restoring an eszett still lands",
            "viele gruesse",
            "viele Gr\u{FC}\u{DF}e",
            expect: "viele Gr\u{FC}\u{DF}e"
        ),
        GuardrailCase("restoring an umlaut still lands", "die aenderungen", "die \u{C4}nderungen", expect: "die \u{C4}nderungen"),
        GuardrailCase(
            "an umlaut left alone is untouched",
            "die \u{C4}nderungen sind drausen",
            "die \u{C4}nderungen sind drau\u{DF}en",
            expect: "die \u{C4}nderungen sind drau\u{DF}en"
        ),
    ]

    @Test(arguments: cases)
    func `an umlaut only ever comes back`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}
