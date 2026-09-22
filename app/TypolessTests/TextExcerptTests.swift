import Foundation
import Testing
@testable import Typoless

/** What the history shows of a change. */
struct TextExcerptTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        /** The highlighted range as location and length, or nil for no range. */
        let highlight: (location: Int, length: Int)?
        let before: String
        let changed: String
        let after: String

        var testDescription: String { name }
    }

    static let cases: Array<Case> = [
        Case(name: "a short field is shown whole", text: "teh cat sat", highlight: (0, 3), before: "", changed: "teh", after: " cat sat"),
        Case(
            name: "a change in the middle keeps both sides",
            text: "the cat sat",
            highlight: (4, 3),
            before: "the ",
            changed: "cat",
            after: " sat"
        ),
        /** A pure insertion has nothing to highlight, which the view has to render anyway. */
        Case(name: "an insertion has an empty middle", text: "the cat", highlight: (7, 0), before: "the cat", changed: "", after: ""),
        /** Nothing to centre on, so the field is clipped from the start instead. */
        Case(
            name: "no range falls back to the start of the field",
            text: "the cat sat",
            highlight: nil,
            before: "the cat sat",
            changed: "",
            after: ""
        ),
        /** Emoji and accents must not be cut mid-character by the offset maths. */
        Case(
            name: "counts characters, not UTF-16 units",
            text: "I 👍 teh cat",
            highlight: (5, 3),
            before: "I 👍 ",
            changed: "teh",
            after: " cat"
        ),
    ]

    @Test(arguments: cases)
    func `the excerpt splits around the change`(_ row: Case) {
        // Arrange
        let range = row.highlight.map { CFRange(location: $0.location, length: $0.length) }

        // Act
        let excerpt = TextExcerpt.build(from: row.text, highlighting: range)

        // Assert
        #expect(excerpt.before == row.before)
        #expect(excerpt.changed == row.changed)
        #expect(excerpt.after == row.after)
    }

    /** The case that matters: one small fix inside a field far longer than the window. */
    @Test func `a long field is trimmed to the change`() {
        // Arrange
        let long = String(repeating: "a", count: 300) + "teh" + String(repeating: "b", count: 300)

        // Act
        let excerpt = TextExcerpt.build(from: long, highlighting: CFRange(location: 300, length: 3))

        // Assert
        #expect(excerpt.changed == "teh")
        #expect(excerpt.before == "…" + String(repeating: "a", count: TextExcerpt.contextCharacters))
        #expect(excerpt.after == String(repeating: "b", count: TextExcerpt.contextCharacters) + "…")
    }
}
