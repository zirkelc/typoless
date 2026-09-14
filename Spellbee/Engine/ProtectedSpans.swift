import Foundation

/**
 Parts of the text nothing is allowed to touch.

 Some spans look like bad writing to a language model and are in fact exactly
 right: a URL has no spaces after its punctuation, a Slack handle is
 deliberately lowercase, an identifier in code is spelled the way the code
 spells it. Correcting any of those breaks something.

 These are used twice over. `MaskedText` swaps them for markers before the model
 is asked, and the guardrail vetoes any edit that lands in one afterwards. The
 second is not made redundant by the first: a model can still move the text
 around a marker, and a span that straddles a chunk boundary is only partly
 hidden.

 Hiding them was once argued against here, on the grounds that text with holes
 punched in it reads as broken to a model and makes its other corrections worse.
 That turned out to be false, and expensively so. Measured on Apple's on-device
 model, a German line whose only fault was one misspelt word was corrected in
 none of six attempts with the link left in and in all six with the link
 masked. The link was not merely surviving the pass, it was costing the pass.
 */
enum ProtectedSpans {
    /// Handles, hashtags, fenced and inline code, and anything with a scheme.
    private static let patterns = [
        #"`[^`]*`"#,
        #"```[\s\S]*?```"#,
        #"(?<![\w])[@#][\w.-]+"#,
        #"[a-zA-Z][a-zA-Z0-9+.-]*://\S+"#,
        #"\S+@\S+\.\S+"#,
        /**
         An emoji shortcode. The body must contain a letter and must not be
         flanked by digits, or `10:30:45` protects `:30:` and the whole chunk is
         then thrown away for an edit that never touched anything.
         */
        #"(?<![0-9]):[a-z0-9_+-]*[a-z][a-z0-9_+-]*:(?![0-9])"#,
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
