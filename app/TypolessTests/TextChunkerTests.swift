import Testing
@testable import Typoless

/**
 Chunks never own the whitespace between them.

 The chunker hands each piece to the model on its own. If a piece carries the
 space or newline that separates it from the next one, the model replies without
 it, and the diff reads the loss as ordinary spacing, which is exactly the kind
 of change the guardrail is built to allow. Two words end up glued together and a
 paragraph break disappears.
 */
struct TextChunkerTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String

        var testDescription: String { name }
    }

    static let sentence = "Wir haben das Thema gestern lange besprochen. "
    static let paragraph = String(repeating: sentence, count: 14)

    static let cases: Array<Case> = [
        Case(name: "a line short enough to send whole", text: "teh cat sat"),
        Case(name: "two lines", text: "hallo anna\nwie gehts"),
        Case(name: "blank lines between", text: "one\n\n\ntwo"),
        Case(name: "a leading indent", text: "    hallo anna"),
        Case(name: "a trailing newline", text: "hallo anna\n"),
        Case(name: "nothing but whitespace", text: "   \n  \n"),
        Case(name: "a long paragraph split into several", text: paragraph),
        Case(name: "a long paragraph then a signature", text: paragraph + "\nViele gruesse, Chris"),
        Case(name: "a long line with no sentence marks", text: String(repeating: "wort ", count: 200)),
        Case(name: "non-BMP characters in a long line", text: paragraph + " 👍 Schluss."),
    ]

    @Test(arguments: cases)
    func `the chunks cover the text and hold no separating whitespace`(_ row: Case) {
        // Arrange
        let text = row.text

        // Act
        let ranges = TextChunker.chunks(of: text)

        // Assert
        var covered = ""
        var cursor = text.startIndex
        for range in ranges {
            covered += text[cursor..<range.lowerBound]
            covered += text[range]
            cursor = range.upperBound
        }
        covered += text[cursor...]

        let holdsNewline = ranges.contains { text[$0].contains(where: \.isNewline) }
        let holdsEdge = ranges.contains {
            text[$0].first?.isWhitespace == true || text[$0].last?.isWhitespace == true
        }

        #expect(covered == text)
        #expect(!holdsNewline)
        #expect(!holdsEdge)
    }
}
