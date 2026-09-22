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
