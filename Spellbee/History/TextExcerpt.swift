import Foundation

/**
 A readable window onto one change inside a possibly very long field.

 Split into three plain pieces rather than built as styled text, so the offset
 arithmetic, which is the part that can be wrong, is a function of a string and a
 range and nothing else. The view decides what the pieces look like.
 */
struct TextExcerpt: Equatable {
    /** How much unchanged text to keep either side, in characters. */
    static let contextCharacters = 90

    /** Unchanged text before the change, with a leading ellipsis if it was cut. */
    let before: String
    /** The changed text itself, empty when the change was a pure insertion. */
    let changed: String
    /** Unchanged text after the change, with a trailing ellipsis if it was cut. */
    let after: String

    /**
     Nil range means no change could be located, in which case there is nothing
     to centre on and the excerpt is just the start of the field.
     */
    static func build(from text: String, highlighting range: CFRange?) -> TextExcerpt {
        /**
         An empty result from a non-empty range means the boundary fell inside a
         character and was rounded away, which showed the row with no highlight
         at all rather than admitting it could not place one.
         */
        guard
            let range,
            let changed = Range(NSRange(location: range.location, length: range.length), in: text),
            !(changed.isEmpty && range.length > 0)
        else {
            return TextExcerpt(before: clip(text), changed: "", after: "")
        }

        let start = text.index(changed.lowerBound, offsetBy: -contextCharacters, limitedBy: text.startIndex)
            ?? text.startIndex
        let end = text.index(changed.upperBound, offsetBy: contextCharacters, limitedBy: text.endIndex)
            ?? text.endIndex

        let leading = (start > text.startIndex ? "…" : "") + String(text[start..<changed.lowerBound])
        let trailing = String(text[changed.upperBound..<end]) + (end < text.endIndex ? "…" : "")

        return TextExcerpt(
            before: leading,
            changed: String(text[changed]),
            after: trailing
        )
    }

    /** Something has to bound a field with no detectable change in it. */
    private static func clip(_ text: String) -> String {
        let limit = contextCharacters * 2

        guard text.count > limit else { return text }

        return String(text.prefix(limit)) + "…"
    }
}
