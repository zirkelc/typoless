import Testing
@testable import Typoless

/** Links, handles, code and addresses are never edited. */
struct ProtectedSpansTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase(
            "url untouched",
            "check http://foo.com/Bar now",
            "Check http://foo.com/bar now.",
            expect: "Check http://foo.com/Bar now."
        ),
        GuardrailCase(
            "handle untouched",
            "ask @chris.cook about it",
            "Ask @Chris.Cook about it.",
            expect: "Ask @chris.cook about it."
        ),
        GuardrailCase("code untouched", "call `getFoo` first", "Call `getfoo` first.", expect: "Call `getFoo` first."),
        GuardrailCase(
            "email untouched",
            "mail me at Chris@Foo.com ok",
            "Mail me at chris@foo.com ok.",
            expect: "Mail me at Chris@Foo.com ok."
        ),
    ]

    @Test(arguments: cases)
    func `the protected text is kept, the rest is corrected`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/** Protected text also stops insertions. */
struct ProtectedTextStopsInsertionsTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase("a comma inside a code span", "run `foo bar` now", "run `foo, bar` now", expect: "run `foo bar` now"),
        GuardrailCase(
            "a stop inside a url",
            "see https://a.example/b now",
            "see https://a.example/b. now",
            expect: "see https://a.example/b now"
        ),
        /**
         Straying into a URL is not the same as rewriting the user's prose, so it must
         not out-vote the corrections that came with it.
         */
        GuardrailCase(
            "handles do not cost the typo fix",
            "hey @Anna und @Bob, teh deploy ist durch",
            "hey @anna und @bob, the deploy ist durch",
            expect: "hey @Anna und @Bob, the deploy ist durch"
        ),
    ]

    @Test(arguments: cases)
    func `nothing is inserted into protected text`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/**
 Which characters count as an emoji, asked of the span finder directly.

 The guardrail refuses a dropped symbol for its own reasons, so going through
 it cannot tell whether a character was hidden from the model, and hiding it is
 what keeps the model from rewriting the sentence around it.
 */
struct EmojiSpansTests {
    @Test(arguments: ["🎉", "❤️", "❤", "✔", "☺", "⚠", "™", "©", "®", "👍🏽", "🇩🇪", "👨‍👩‍👧", "1️⃣"])
    func `an emoji is protected, however it was typed`(_ emoji: String) {
        // Arrange
        let text = "ship it \(emoji) today"

        // Act
        let spans = ProtectedSpans.find(in: text)

        // Assert
        #expect(spans.count == 1)
        #expect(spans.first.map { String(text[$0]) } == emoji)
    }

    /** The keycap bases are emoji by property, and freezing every digit would freeze the numbers. */
    @Test(arguments: ["5", "#", "*", "→", "★", "•", "é"])
    func `an everyday character is not an emoji`(_ character: String) {
        // Arrange
        let text = "ship \(character) today"

        // Act
        let spans = ProtectedSpans.find(in: text)

        // Assert
        #expect(spans.isEmpty)
    }
}
