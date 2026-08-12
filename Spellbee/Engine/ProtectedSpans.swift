import Foundation

/**
 Parts of the text nothing is allowed to touch.

 Some spans look like bad writing to a language model and are in fact exactly
 right: a URL has no spaces after its punctuation, a Slack handle is
 deliberately lowercase, an identifier in code is spelled the way the code
 spells it. Correcting any of those breaks something.

 These are found in the original text and used to veto edits that overlap them,
 rather than being hidden from the model. Text with holes punched in it reads as
 broken to the model, which makes its other corrections worse.
 */
enum ProtectedSpans {
    /// Handles, hashtags, fenced and inline code, and anything with a scheme.
    private static let patterns = [
        #"`[^`]*`"#,
        #"```[\s\S]*?```"#,
        #"(?<![\w])[@#][\w.-]+"#,
        #"[a-zA-Z][a-zA-Z0-9+.-]*://\S+"#,
        #"\S+@\S+\.\S+"#,
        #":[a-z0-9_+-]+:"#,
    ]

    static func find(in text: String) -> [Range<String.Index>] {
        var spans: [Range<String.Index>] = []
        let whole = NSRange(text.startIndex..., in: text)

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }

            for match in expression.matches(in: text, range: whole) {
                if let range = Range(match.range, in: text) {
                    spans.append(range)
                }
            }
        }

        /** Links the detector finds but the patterns miss, like bare www addresses. */
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: whole) {
                if let range = Range(match.range, in: text) {
                    spans.append(range)
                }
            }
        }

        spans += emoji(in: text)

        return spans
    }

    /**
     Emoji as they are actually typed, rather than as `:shortcode:`.

     A model will happily swap one for another, and the swap survives every
     other check because an emoji is neither a word nor punctuation. Which
     emoji someone chose is not a spelling question, so none of them are ours
     to change.
     */
    private static func emoji(in text: String) -> [Range<String.Index>] {
        var spans: [Range<String.Index>] = []

        for index in text.indices where text[index].isEmoji {
            spans.append(index..<text.index(after: index))
        }

        return spans
    }
}

private extension Character {
    /**
     Whether this reads as an emoji rather than as text.

     `isEmoji` alone is true of plain digits and `#`, which carry emoji
     presentation only when followed by a variation selector, so the presented
     form is what is asked for.
     */
    var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }

        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}
