import Foundation
import Testing
@testable import Typoless

/**
 Changes stay minimal.

 A correction touches only the words it had to. This is what lets the app write
 back without flattening a field: the characters carrying a mention, a link or
 any other formatting are never part of an edit, so they are never rewritten.
 */
struct MinimalEditsTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let original: String
        let corrected: String
        /** The original text of every edit, in order. */
        let expected: Array<String>

        var testDescription: String { name }
    }

    static let cases: Array<Case> = [
        Case(
            name: "one word in a long line",
            original: "hey @chris, can you check teh deploy on https://ci.example.com today",
            corrected: "hey @chris, can you check the deploy on https://ci.example.com today",
            expected: ["teh"]
        ),
        Case(
            name: "two far apart",
            original: "i went to teh shop and bougth milk",
            corrected: "I went to the shop and bought milk",
            expected: ["i", "teh", "bougth"]
        ),
        Case(name: "nothing to do", original: "All good here.", corrected: "All good here.", expected: []),
        Case(
            name: "trailing punctuation only",
            original: "see you tomorrow",
            corrected: "see you tomorrow.",
            expected: ["tomorrow"]
        ),
    ]

    @Test(arguments: cases)
    func `only the words that changed are touched`(_ row: Case) {
        // Arrange
        let original = row.original

        // Act
        let touched = TextDiff.edits(from: original, to: row.corrected).map(\.original)

        // Assert
        #expect(touched == row.expected)
    }
}

/** The span an undo has to put back. */
struct DifferingSpanTests {
    struct Span: Equatable, Sendable {
        let location: Int
        let length: Int
        let replacement: String
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let before: String
        let after: String
        /** Nil where the two texts are the same. */
        let expected: Span?

        var testDescription: String { name }
    }

    static let cases: Array<Case> = [
        Case(name: "identical", before: "same", after: "same", expected: nil),
        Case(name: "one word", before: "the cat sat", after: "the dog sat", expected: Span(location: 4, length: 3, replacement: "dog")),
        Case(name: "insertion", before: "hello world", after: "hello big world", expected: Span(location: 6, length: 0, replacement: "big ")),
        Case(name: "deletion", before: "hello big world", after: "hello world", expected: Span(location: 6, length: 4, replacement: "")),
        Case(name: "shared letters at both ends", before: "recieve", after: "receive", expected: Span(location: 3, length: 2, replacement: "ei")),
    ]

    @Test(arguments: cases)
    func `the span covers exactly what differs`(_ row: Case) {
        // Arrange
        let before = row.before

        // Act
        let span = TextDiff.differingSpan(from: before, to: row.after).map {
            Span(location: $0.range.location, length: $0.range.length, replacement: $0.replacement)
        }

        // Assert
        #expect(span == row.expected)
    }
}
