import Foundation

/**
 What a field holds, rebuilt from its parts rather than read from its value.

 A rich composer can show what its value leaves out. Slack is the case that
 found this: a message ending in a smile reports its value as the sentence with
 the emoji replaced by two newlines, and `kAXNumberOfCharacters` agrees with
 that shorter version, so nothing in the text says anything is missing.
 Correcting that text and writing it back deleted the emoji and turned it into
 two blank lines.

 Its subtree tells the truth, in order:

     AXStaticText  "hello "
     AXImage       "smile emoji"
     AXStaticText  " world"

 which is `hello :smile: world`, the text the user typed. A shortcode is what
 they wrote in the first place and what the message renders from when it is
 sent, so it is both readable to the model and safe to write back.

 Kept a plain function of a list of parts, so the rule can be tested without an
 accessibility tree.
 */
enum FieldPart: Equatable, Sendable {
    case text(String)
    /** An image the field draws in place of text, named by its description. */
    case emoji(String)
    /** Anything else: a file, a button, a chip. Nothing a string can carry. */
    case unrepresentable(role: String)
}

enum FieldText {
    /**
     The parts as one string, or nil when any of them cannot be written back.

     Nil is not a failure to read: it means this field holds something a plain
     string would destroy, and the caller must leave the field alone rather than
     write a version of it that is missing a piece.
     */
    static func assemble(_ parts: [FieldPart]) -> String? {
        var text = ""

        for part in parts {
            switch part {
            case .text(let value):
                text += value
            case .emoji(let name):
                text += ":\(name):"
            case .unrepresentable:
                return nil
            }
        }

        return text
    }

    /**
     The shortcode name inside an image's description.

     Slack describes the image as "smile emoji", and a custom one as
     "party-parrot emoji". Anything that does not name itself as an emoji is
     something else in disguise, so it is refused rather than guessed at.
     */
    static func emojiName(fromDescription description: String?) -> String? {
        guard let description else { return nil }

        let trimmed = description.trimmingCharacters(in: .whitespaces)
        let suffix = " emoji"

        guard trimmed.count > suffix.count, trimmed.lowercased().hasSuffix(suffix) else { return nil }

        let name = String(trimmed.dropLast(suffix.count))
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        return name.isEmpty ? nil : name
    }
}
