import Testing
@testable import Typoless

/**
 Protected text is hidden from the model, then put back.

 Hiding a link is only safe if it comes back character for character, and only
 useful if the model still sees a sentence.
 */
struct MaskedTextTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        /** Plays the model: takes the masked text and returns its reply. */
        let reply: @Sendable (String) -> String
        /** Nil where the reply has to abandon the chunk. */
        let expected: String?

        var testDescription: String { name }
    }

    static let elevenHandles = "a " + (0..<11).map { "@user\($0)" }.joined(separator: " b ") + " c"

    static let cases: Array<Case> = [
        /** The model returns the marker untouched, which is the ordinary case. */
        Case(
            name: "a link is hidden and restored",
            text: "schau mal hier github.com/a/b",
            reply: { $0.replacingOccurrences(of: "schau", with: "Schau") },
            expected: "Schau mal hier github.com/a/b"
        ),
        Case(
            name: "several spans keep their own places",
            text: "ping @anna about `run.sh` at github.com/a/b",
            reply: { $0 },
            expected: "ping @anna about `run.sh` at github.com/a/b"
        ),
        Case(
            name: "text with nothing to hide is untouched",
            text: "hallo welt",
            reply: { $0 + "." },
            expected: "hallo welt."
        ),
        /** The failure paths, which are the whole reason this is not a plain substitution. */
        Case(
            name: "a dropped marker abandons the chunk",
            text: "schau mal hier github.com/a/b",
            reply: { $0.replacingOccurrences(of: MaskedText.marker(0), with: "") },
            expected: nil
        ),
        Case(
            name: "a duplicated marker abandons the chunk",
            text: "schau mal hier github.com/a/b",
            reply: { $0 + " " + MaskedText.marker(0) },
            expected: nil
        ),
        Case(
            name: "a rewritten marker abandons the chunk",
            text: "schau mal hier github.com/a/b",
            reply: { $0.replacingOccurrences(of: MaskedText.marker(0), with: "[link]") },
            expected: nil
        ),
        /**
         The link is the whole point: whatever the model does to the marker's
         surroundings, the link itself cannot be edited, because it was never shown.
         */
        Case(
            name: "the model cannot damage what it never saw",
            text: "mail an chris@example.com bitte",
            reply: { $0.replacingOccurrences(of: "mail", with: "Mail") },
            expected: "Mail an chris@example.com bitte"
        ),
        /**
         Overlapping spans are the normal case, not an edge case: a link is matched by
         its own pattern and by the data detector both.
         */
        Case(
            name: "overlapping spans do not nest",
            text: "siehe https://github.com/a/b hier",
            reply: { $0 },
            expected: "siehe https://github.com/a/b hier"
        ),
        /**
         A marker sitting where a sentence starts comes back capitalised, which names
         the same span and must not cost the chunk.
         */
        Case(
            name: "a marker that came back capitalised still restores",
            text: "github.com/a/b is the one",
            reply: { $0.replacingOccurrences(of: MaskedText.marker(0), with: MaskedText.marker(0).capitalized) },
            expected: "github.com/a/b is the one"
        ),
        /**
         `ZQX1` opens `ZQX10`, so a message with eleven hidden spans has to restore
         the long markers first or the short ones match inside them.
         */
        Case(
            name: "eleven spans do not collide",
            text: elevenHandles,
            reply: { $0 },
            expected: elevenHandles
        ),
    ]

    @Test(arguments: cases)
    func `the reply is restored or abandoned`(_ row: Case) {
        // Arrange
        let masked = MaskedText.mask(row.text, protecting: ProtectedSpans.find(in: row.text))
        let reply = row.reply(masked.text)

        // Act
        let restored = masked.restore(reply)

        // Assert
        #expect(restored == row.expected)
    }
}
