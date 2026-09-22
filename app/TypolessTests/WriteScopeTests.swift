import Foundation
import Testing
@testable import Typoless

/** When the whole field may be rewritten. */
struct WriteScopeTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let location: Int
        let length: Int
        let text: String
        let expected: Bool

        var testDescription: String { name }
    }

    static let field = "the cat sat on the mat"

    static let cases: Array<Case> = [
        Case(name: "the whole field may be rewritten", location: 0, length: field.utf16.count, text: field, expected: true),
        Case(name: "a selection at the start may not", location: 0, length: 3, text: field, expected: false),
        Case(name: "a selection in the middle may not", location: 4, length: 3, text: field, expected: false),
        Case(name: "a selection reaching the end may not", location: 4, length: field.utf16.count - 4, text: field, expected: false),
        Case(name: "an empty field is trivially whole", location: 0, length: 0, text: "", expected: true),
        /** The case that flattened a Chrome field: a small fix inside a long one. */
        Case(
            name: "28 characters inside 825 may not",
            location: 100,
            length: 28,
            text: String(repeating: "x", count: 825),
            expected: false
        ),
        /** A range running past the end still counts, since nothing outside it survives anyway. */
        Case(name: "a range past the end still counts", location: 0, length: 9_999, text: field, expected: true),
    ]

    @Test(arguments: cases)
    func `only a range over the whole field covers it`(_ row: Case) {
        // Arrange
        let range = CFRange(location: row.location, length: row.length)

        // Act
        let covers = WriteScope.coversWholeField(range, of: row.text)

        // Assert
        #expect(covers == row.expected)
    }
}
