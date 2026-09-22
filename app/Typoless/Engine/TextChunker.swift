import NaturalLanguage

/**
 Splits text into pieces small enough to correct in one request.

 The on-device model shares a fixed context between what it is given and what it
 writes back, so a long message has to be broken up. Lines are the unit: they
 are what people actually compose in, they keep list items and quoted replies
 from bleeding into each other, and working line by line means the separators
 between them are never sent to the model and so can never be disturbed.
 */
enum TextChunker {
    /**
     Longest piece sent in one request, in characters.

     Deliberately well under what the context could hold. The budget covers the
     instructions, the text, and the model's reply, and a chunk that overflows
     produces a truncated correction rather than an error.
     */
    static let characterBudget = 600

    static func chunks(of text: String) -> [Range<String.Index>] {
        var chunks: [Range<String.Index>] = []
        var index = text.startIndex

        while index < text.endIndex {
            while index < text.endIndex, text[index].isNewline {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }

            var end = index
            while end < text.endIndex, !text[end].isNewline {
                end = text.index(after: end)
            }

            chunks.append(contentsOf: split(text, in: index..<end).compactMap { trimming(text, $0) })
            index = end
        }

        return chunks
    }

    /**
     Narrows a chunk so it owns no whitespace at either end.

     A chunk must never contain the whitespace that separates it from the next
     one. `NLTokenizer` does not clamp its tokens to the range it is asked
     about, so a sentence token routinely runs past the end of the line and
     takes the newline with it, and its tokens carry their trailing space in any
     case. Either way the model is handed a separator, replies without it, and
     the diff reads the loss as ordinary spacing, which the guardrail allows.
     The result was two words glued together and a paragraph break deleted.

     Nil where a chunk is nothing but whitespace, which is not worth a request.
     */
    private static func trimming(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        var lower = range.lowerBound
        var upper = range.upperBound

        while lower < upper, text[lower].isWhitespace {
            lower = text.index(after: lower)
        }

        while lower < upper, text[text.index(before: upper)].isWhitespace {
            upper = text.index(before: upper)
        }

        return lower < upper ? lower..<upper : nil
    }

    /** Breaks an over-long line on sentence boundaries rather than mid-thought. */
    private static func split(_ text: String, in range: Range<String.Index>) -> [Range<String.Index>] {
        guard text.distance(from: range.lowerBound, to: range.upperBound) > characterBudget else {
            return [range]
        }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var chunks: [Range<String.Index>] = []
        var current: Range<String.Index>?

        tokenizer.enumerateTokens(in: range) { token, _ in
            /** The tokenizer answers about the string, not about the range it was given. */
            let sentence = token.clamped(to: range)

            guard !sentence.isEmpty else { return true }

            guard let existing = current else {
                current = sentence
                return true
            }

            let combined = existing.lowerBound..<sentence.upperBound
            if text.distance(from: combined.lowerBound, to: combined.upperBound) <= characterBudget {
                current = combined
            } else {
                chunks.append(existing)
                current = sentence
            }

            return true
        }

        if let current {
            chunks.append(current)
        }

        /**
         A line with no sentence marks at all yields one token the size of the
         line, so the budget bounded nothing: a long run-on chat message went to
         the model in a single request and overflowed its context, which comes
         back as a truncated correction. Anything still over budget is cut on
         word boundaries.
         */
        return (chunks.isEmpty ? [range] : chunks).flatMap { splitOnWords(text, in: $0) }
    }

    private static func splitOnWords(_ text: String, in range: Range<String.Index>) -> [Range<String.Index>] {
        guard text.distance(from: range.lowerBound, to: range.upperBound) > characterBudget else {
            return [range]
        }

        var chunks: [Range<String.Index>] = []
        var start = range.lowerBound

        while start < range.upperBound {
            var end = text.index(start, offsetBy: characterBudget, limitedBy: range.upperBound)
                ?? range.upperBound

            /** Back up to a space so a word is never cut in half. */
            if end < range.upperBound {
                var candidate = end
                while candidate > start, !text[text.index(before: candidate)].isWhitespace {
                    candidate = text.index(before: candidate)
                }

                if candidate > start { end = candidate }
            }

            chunks.append(start..<end)
            start = end
        }

        return chunks
    }
}
