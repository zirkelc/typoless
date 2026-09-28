import Foundation
import Testing
@testable import Typoless

/**
 What the history shows of a change.

 Two properties matter and both are easy to get wrong by an offset. The window
 has to hold every change with its surrounding words, and each highlight has to
 land on the words that changed, not on the stretch between the first and the
 last of them.
 */
struct TextExcerptTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        /** The highlighted ranges as location and length. */
        let highlights: Array<(location: Int, length: Int)>
        let expectedText: String
        /** What each highlight should read, in order. */
        let expectedHighlights: Array<String>

        var testDescription: String { name }
    }

    static let cases: Array<Case> = [
        Case(
            name: "a short field is shown whole",
            text: "teh cat sat",
            highlights: [(0, 3)],
            expectedText: "teh cat sat",
            expectedHighlights: ["teh"]
        ),
        Case(
            name: "a change in the middle keeps both sides",
            text: "the cat sat",
            highlights: [(4, 3)],
            expectedText: "the cat sat",
            expectedHighlights: ["cat"]
        ),
        /** The case that started this: two words changed, not the line between them. */
        Case(
            name: "two changes are marked separately",
            text: "Check this to-do",
            highlights: [(0, 5), (11, 5)],
            expectedText: "Check this to-do",
            expectedHighlights: ["Check", "to-do"]
        ),
        /** A pure insertion has nothing to mark, and must not mark something else. */
        Case(
            name: "an insertion marks nothing",
            text: "the cat",
            highlights: [(7, 0)],
            expectedText: "the cat",
            expectedHighlights: [""]
        ),
        /** Nothing to centre on, so the field is clipped from the start instead. */
        Case(
            name: "no range falls back to the start of the field",
            text: "the cat sat",
            highlights: [],
            expectedText: "the cat sat",
            expectedHighlights: []
        ),
        /** Emoji and accents must not be cut mid-character by the offset maths. */
        Case(
            name: "counts characters, not UTF-16 units",
            text: "I 👍 teh cat",
            highlights: [(5, 3)],
            expectedText: "I 👍 teh cat",
            expectedHighlights: ["teh"]
        ),
    ]

    @Test(arguments: cases)
    func `every change is marked where it is`(_ row: Case) {
        // Arrange
        let ranges = row.highlights.map { CFRange(location: $0.location, length: $0.length) }

        // Act
        let excerpt = TextExcerpt.build(from: row.text, highlighting: ranges)

        // Assert
        #expect(excerpt.text == row.expectedText)
        #expect(excerpt.highlights.map { String(excerpt.text[$0]) } == row.expectedHighlights)
    }

    /** The case that matters: one small fix inside a field far longer than the window. */
    @Test func `a long field is trimmed to the change`() {
        // Arrange
        let long = String(repeating: "a", count: 300) + "teh" + String(repeating: "b", count: 300)

        // Act
        let excerpt = TextExcerpt.build(from: long, highlighting: [CFRange(location: 300, length: 3)])

        // Assert
        let context = TextExcerpt.contextCharacters
        #expect(excerpt.text == "…" + String(repeating: "a", count: context)
            + "teh" + String(repeating: "b", count: context) + "…")

        let highlight = try? #require(excerpt.highlights.first)
        #expect(highlight.map { String(excerpt.text[$0]) } == "teh")
    }

    /** Two changes far apart share one window, so the middle is not cut out of it. */
    @Test func `changes far apart are both inside the window`() {
        // Arrange
        let long = "teh" + String(repeating: " word", count: 60) + " cta"

        // Act
        let excerpt = TextExcerpt.build(
            from: long,
            highlighting: [
                CFRange(location: 0, length: 3),
                CFRange(location: long.utf16.count - 3, length: 3),
            ]
        )

        // Assert
        #expect(excerpt.highlights.count == 2)
        #expect(excerpt.highlights.map { String(excerpt.text[$0]) } == ["teh", "cta"])
    }
}
