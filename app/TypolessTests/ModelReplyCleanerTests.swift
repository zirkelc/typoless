import Testing
@testable import Typoless

/** A free-text model reply is unwrapped down to the corrected text. */
struct ModelReplyCleanerTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let reply: String
        let expected: String

        var testDescription: String { name }
    }

    static let cases: Array<Case> = [
        Case(name: "plain", reply: "Hello world.", expected: "Hello world."),
        Case(name: "reasoning block", reply: "<think>The user wants...</think>\nHello world.", expected: "Hello world."),
        Case(name: "preamble", reply: "Here is the corrected text:\n\nHello world.", expected: "Hello world."),
        Case(name: "quoted", reply: "\"Hello world.\"", expected: "Hello world."),
        Case(name: "fenced", reply: "```\nHello world.\n```", expected: "Hello world."),
        Case(name: "reasoning and preamble", reply: "<think>hmm</think>\n\nCorrected:\n\nHello world.", expected: "Hello world."),
        Case(name: "keeps an inner quote", reply: "She said \"hello\" to me.", expected: "She said \"hello\" to me."),
        Case(name: "keeps a real blank line", reply: "Hello world.", expected: "Hello world."),
    ]

    @Test(arguments: cases)
    func `the reply is unwrapped`(_ row: Case) {
        // Arrange
        let reply = row.reply

        // Act
        let result = ModelReplyCleaner.clean(reply)

        // Assert
        #expect(result == row.expected)
    }
}
