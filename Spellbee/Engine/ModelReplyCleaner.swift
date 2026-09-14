import Foundation

/**
 Strips the packaging a model puts around its answer.

 Apple's model is asked for a structured value, so its reply arrives clean. A
 downloaded model answering in free text is not so disciplined: it may narrate
 its reasoning first, introduce the answer, or wrap it in quotation marks. Every
 one of those reads as an enormous edit and would be refused, so the correction
 would silently never happen.

 Deliberately conservative. Removing too little costs one refused correction;
 removing too much would cut into the user's own words.
 */
enum ModelReplyCleaner {
    /**
     - Parameter source: The text the model was asked about, so its own
       punctuation is never mistaken for the model's packaging.
     */
    static func clean(_ reply: String, of source: String = "") -> String {
        var text = reply.trimmed

        /**
         Reasoning block, which some models emit before answering. Only when the
         reply opens with one, and matched from the end, so the same tag
         appearing in the user's own text cannot swallow everything before it.
         */
        if text.hasPrefix("<think>"), let end = text.range(of: "</think>", options: .backwards) {
            text = String(text[end.upperBound...])
        }

        text = text.trimmed

        /**
         An introduction sits on its own line before the answer. Which block is
         the answer cannot be settled by position, though: models explain
         themselves after the correction at least as often as before it. The
         answer is the block closest in length to what was asked about.
         */
        let blocks = text.components(separatedBy: "\n\n").map(\.trimmed).filter { !$0.isEmpty }

        if blocks.count > 1, !source.isEmpty {
            text = blocks.min { abs($0.count - source.count) < abs($1.count - source.count) } ?? text
        } else if let last = blocks.last, blocks.count > 1 {
            text = last
        }

        text = stripFence(from: text)
        text = stripWrapping("\"", from: text, unless: source)
        text = stripWrapping("'", from: text, unless: source)

        return text
    }

    /**
     Removes a fenced code block, including the language tag some models add.

     Stripping only the backticks left `text` sitting on the first line, which
     then reads as part of the user's writing.
     */
    private static func stripFence(from text: String) -> String {
        guard text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6 else { return text }

        var inner = Substring(text.dropFirst(3).dropLast(3))

        if let firstBreak = inner.firstIndex(where: \.isNewline) {
            let tag = inner[..<firstBreak]

            /** A language tag is one word; anything longer is the answer itself. */
            if !tag.isEmpty, !tag.contains(" ") {
                inner = inner[inner.index(after: firstBreak)...]
            }
        }

        return String(inner).trimmed
    }

    /**
     Removes a matched pair, and only a matched pair, and only one the user did
     not write themselves.

     A quoted line is ordinary text. Stripping the marks because the model
     echoed them back deleted punctuation the user had typed, and the loss
     landed on the first and last word where it passed as capitalisation and
     punctuation.
     */
    private static func stripWrapping(_ mark: String, from text: String, unless source: String) -> String {
        guard
            text.count > mark.count * 2,
            text.hasPrefix(mark),
            text.hasSuffix(mark),
            !(source.hasPrefix(mark) && source.hasSuffix(mark))
        else {
            return text
        }

        return String(text.dropFirst(mark.count).dropLast(mark.count)).trimmed
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
