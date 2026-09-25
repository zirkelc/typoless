import Testing
@testable import Typoless

/**
 A field is rebuilt from its parts when its value does not carry them all.

 Slack found this. Its composer reports a message with an emoji in it as the
 text with two newlines where the emoji is, and `kAXNumberOfCharacters` agrees
 with that version, so nothing in the text says anything is missing. Its subtree
 says it plainly, in order: the words, an image called "smile emoji", the rest
 of the words.
 */
struct FieldTextTests {
    @Test func `an emoji image becomes the shortcode it was typed as`() {
        // Arrange
        let parts: [FieldPart] = [.text("hello "), .emoji("smile"), .text(" world")]

        // Act
        let text = FieldText.assemble(parts)

        // Assert
        #expect(text == "hello :smile: world")
    }

    @Test func `a field of plain text is unchanged by being rebuilt`() {
        // Arrange
        let parts: [FieldPart] = [.text("hello world")]

        // Act
        let text = FieldText.assemble(parts)

        // Assert
        #expect(text == "hello world")
    }

    /**
     Nil means "leave this field alone". A string that silently dropped the part
     it could not carry is what deleted a user's emoji in the first place.
     */
    @Test func `a part that cannot be written refuses the whole field`() {
        // Arrange
        let parts: [FieldPart] = [.text("see "), .unrepresentable(role: "AXButton"), .text(" here")]

        // Act
        let text = FieldText.assemble(parts)

        // Assert
        #expect(text == nil)
    }

    @Test(arguments: [
        ("smile emoji", "smile"),
        ("party-parrot emoji", "party-parrot"),
        ("  thumbsup emoji  ", "thumbsup"),
        (":smile: emoji", "smile"),
    ])
    func `an emoji names itself in its description`(_ row: (description: String, name: String)) {
        // Arrange
        let description = row.description

        // Act
        let name = FieldText.emojiName(fromDescription: description)

        // Assert
        #expect(name == row.name)
    }

    /** Anything that does not say it is an emoji is something else in disguise. */
    @Test(arguments: ["a photo of a cat", "emoji", " emoji", "attachment", ""])
    func `an image that is not an emoji is not guessed at`(_ description: String) {
        // Arrange
        let candidate = description

        // Act
        let name = FieldText.emojiName(fromDescription: candidate)

        // Assert
        #expect(name == nil)
    }
}
