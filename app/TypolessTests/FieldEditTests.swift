import Foundation
import Testing
@testable import Typoless

/** Positions after the changes land. */
struct FieldEditTests {
    /** "teh cat" -> "the cats": one same-length fix early, one growth later. */
    static let sample = [
        FieldEdit(range: CFRange(location: 0, length: 3), replacement: "the"),
        FieldEdit(range: CFRange(location: 4, length: 3), replacement: "cats"),
    ]

    struct CaretCase: Sendable, CustomTestStringConvertible {
        let name: String
        let edits: Array<FieldEdit>
        let offset: Int
        let expected: Int

        var testDescription: String { name }
    }

    static let caretCases: Array<CaretCase> = [
        CaretCase(name: "before every change", edits: sample, offset: 0, expected: 0),
        CaretCase(name: "between them", edits: sample, offset: 4, expected: 4),
        CaretCase(name: "after both", edits: sample, offset: 7, expected: 8),
        CaretCase(name: "inside a changed word", edits: sample, offset: 5, expected: 8),
        CaretCase(name: "no changes at all", edits: [], offset: 12, expected: 12),
    ]

    @Test(arguments: caretCases)
    func `the caret follows the text it was in`(_ row: CaretCase) {
        // Arrange
        let edits = row.edits

        // Act
        let position = edits.caretPosition(from: row.offset)

        // Assert
        #expect(position == row.expected)
    }

    struct Landed: Equatable, Sendable {
        let location: Int
        let length: Int
    }

    struct LandedCase: Sendable, CustomTestStringConvertible {
        let name: String
        let edits: Array<FieldEdit>
        let expected: Array<Landed>

        var testDescription: String { name }
    }

    static let landedCases: Array<LandedCase> = [
        LandedCase(
            name: "displaced by what came before",
            edits: sample,
            expected: [Landed(location: 0, length: 3), Landed(location: 4, length: 4)]
        ),
        LandedCase(
            name: "pure deletion has nothing to point at",
            edits: [FieldEdit(range: CFRange(location: 5, length: 1), replacement: "")],
            expected: []
        ),
        LandedCase(
            name: "later change shifted by an earlier deletion",
            edits: [
                FieldEdit(range: CFRange(location: 5, length: 1), replacement: ""),
                FieldEdit(range: CFRange(location: 10, length: 3), replacement: "the"),
            ],
            expected: [Landed(location: 9, length: 3)]
        ),
    ]

    @Test(arguments: landedCases)
    func `each change points at where it landed`(_ row: LandedCase) {
        // Arrange
        let edits = row.edits

        // Act
        let ranges = edits.landedRanges.map { Landed(location: $0.location, length: $0.length) }

        // Assert
        #expect(ranges == row.expected)
    }
}
