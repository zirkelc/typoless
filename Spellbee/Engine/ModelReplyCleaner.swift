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
    static func clean(_ reply: String) -> String {
        var text = reply

        /** Reasoning block, which some models emit before answering. */
        if let end = text.range(of: "</think>") {
            text = String(text[end.upperBound...])
        }

        text = text.trimmed

        /**
         An introduction sits on its own line before the answer, so when the
         reply has several blocks the answer is the last one.
         */
        if let lastBlank = text.range(of: "\n\n", options: .backwards) {
            text = String(text[lastBlank.upperBound...]).trimmed
        }

        text = stripWrapping("```", from: text)
        text = stripWrapping("\"", from: text)
        text = stripWrapping("'", from: text)

        return text
    }

    /** Removes a matched pair, and only a matched pair. */
    private static func stripWrapping(_ mark: String, from text: String) -> String {
        guard
            text.count > mark.count * 2,
            text.hasPrefix(mark),
            text.hasSuffix(mark)
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
