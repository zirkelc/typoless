import Foundation
import Testing
@testable import Typoless

/**
 Which words the app asks about, and which it must never ask about.

 A list that fills with typos is a list nobody reads, and the answer to every
 question here changes what gets corrected from then on, so a wrong question is
 worse than no question.
 */
@MainActor
struct UnknownWordsTests {
    private static func written(_ texts: [String]) -> UnknownWords {
        let words = UnknownWords()

        for text in texts {
            words.record(text, in: .english)
        }

        return words
    }

    @Test
    func `a word written five times is worth asking about`() {
        // Arrange
        let texts = Array(repeating: "we ship it with pnpm today", count: 5)

        // Act
        let words = Self.written(texts)

        // Assert
        #expect(words.suggestions == ["pnpm"])
        #expect(words.count(of: "pnpm") == 5)
    }

    @Test
    func `four times is not enough`() {
        // Arrange
        let texts = Array(repeating: "we ship it with pnpm today", count: 4)

        // Act
        let words = Self.written(texts)

        // Assert
        #expect(words.suggestions.isEmpty)
    }

    /** One message cannot carry a word to five, or a list of names would. */
    @Test
    func `a word repeated inside one message counts once`() {
        // Arrange
        let text = "pnpm pnpm pnpm pnpm pnpm pnpm"

        // Act
        let words = Self.written([text])

        // Assert
        #expect(words.count(of: "pnpm") == 1)
    }

    @Test
    func `a word the dictionary knows is never asked about`() {
        // Arrange
        let texts = Array(repeating: "the meeting is at noon", count: 10)

        // Act
        let words = Self.written(texts)

        // Assert
        #expect(words.suggestions.isEmpty)
    }

    @Test
    func `a word the user has dismissed is not asked about again`() {
        // Arrange
        let words = Self.written(Array(repeating: "we ship it with pnpm today", count: 5))

        // Act
        words.dismiss("pnpm")

        // Assert
        #expect(words.suggestions.isEmpty)
    }

    /** Teaching the Mac the word answers the question, wherever it was answered. */
    @Test
    func `a word already taught to the Mac is not asked about`() {
        // Arrange
        let word = "zqplumb"
        let wasLearned = WordList.isLearned(word)
        WordList.setLearned(true, for: word)
        defer { WordList.setLearned(wasLearned, for: word) }

        // Act
        let words = Self.written(Array(repeating: "we ship it with \(word) today", count: 5))

        // Assert
        #expect(words.suggestions.isEmpty)
    }

    /** The most written first, since that is the one most likely to be theirs. */
    @Test
    func `the words are ordered by how often they are written`() {
        // Arrange
        var texts = Array(repeating: "we ship it with pnpm today", count: 5)
        texts += Array(repeating: "oxlint and pnpm again", count: 6)

        // Act
        let words = Self.written(texts)

        // Assert
        #expect(words.suggestions == ["pnpm", "oxlint"])
    }
}
