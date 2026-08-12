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

        return spans
    }
}
