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

            chunks.append(contentsOf: split(text, in: index..<end))
            index = end
        }

        return chunks
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

        tokenizer.enumerateTokens(in: range) { sentence, _ in
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

        return chunks.isEmpty ? [range] : chunks
    }
}
