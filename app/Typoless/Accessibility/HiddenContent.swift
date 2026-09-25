import Foundation

/**
 Whether a field holds something its text does not mention.

 A rich composer can show what its accessibility *value* leaves out. Slack is
 the case that found this: a message ending in a smile shows the emoji, and the
 value handed to us is the sentence without it, with `kAXNumberOfCharacters`
 agreeing with the short version, so nothing in the text says that anything is
 missing. Overwriting the whole field with that text deleted the emoji from the
 user's message, and nothing in the guardrail could have known, since the
 guardrail only ever sees the text.

 The subtree does say so. Under that same field sit an `AXStaticText` with the
 words and an `AXImage` described as "smile emoji". Anything in there that is
 not text is content a plain string cannot carry.

 Split out of the writer, and kept a plain function of a list of roles, so the
 rule that decides whether a correction may flatten someone's message can be
 tested without an accessibility tree.
 */
enum HiddenContent {
    /**
     Roles that carry text and nothing else, so a field made only of these
     loses nothing by being rewritten as a string.

     A group holds other elements rather than content of its own, and a text
     element is the text we already have. Everything else, an image, an
     attachment, a button, a link with a label of its own, is something the
     value cannot represent.
     */
    private static let textOnly: Set<String> = [
        "AXGroup",
        "AXStaticText",
        "AXTextArea",
        "AXTextField",
        "AXHeading",
        "AXList",
        "AXListMarker",
        "AXParagraph",
        "AXRow",
        "AXCell",
        "AXTable",
        "AXUnknown",
    ]

    /** Whether any of these roles is something a plain string would destroy. */
    static func isLossy(roles: [String]) -> Bool {
        roles.contains { !textOnly.contains($0) }
    }
}
