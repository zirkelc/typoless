import Foundation

/**
 A readable window onto the changes inside a possibly very long field.

 Plain text and offsets rather than styled text, so the arithmetic, which is the
 part that can be wrong, is a function of a string and some ranges and nothing
 else. The view decides what the pieces look like.

 Every change is marked, not the stretch that contains them. One span from the
 first difference to the last is far easier to compute and reads as a lie:
 "chekc this todo" corrected to "Check this to-do" marked the whole line, so an
 app that changed two words claimed to have rewritten the sentence.
 */
struct TextExcerpt: Equatable {
    /** How much unchanged text to keep either side of the outermost change. */
    static let contextCharacters = 90

    /** The window itself, with an ellipsis wherever it was cut. */
    let text: String

    /** What changed, in this string's own coordinates. */
    let highlights: [Range<String.Index>]

    /**
     An empty list of ranges means nothing could be located, in which case there
     is nothing to centre on and the excerpt is just the start of the field.
     */
    static func build(from text: String, highlighting ranges: [CFRange]) -> TextExcerpt {
        /**
         An empty result from a non-empty range means the boundary fell inside a
         character and was rounded away, which showed the row with no highlight
         at all rather than admitting it could not place one.
         */
        let changes = ranges.compactMap { range -> Range<String.Index>? in
            guard
                let converted = Range(NSRange(location: range.location, length: range.length), in: text),
                !(converted.isEmpty && range.length > 0)
            else { return nil }

            return converted
        }
        .sorted { $0.lowerBound < $1.lowerBound }

        guard let first = changes.first, let last = changes.max(by: { $0.upperBound < $1.upperBound }) else {
            return TextExcerpt(text: clip(text), highlights: [])
        }

        let start = text.index(first.lowerBound, offsetBy: -contextCharacters, limitedBy: text.startIndex)
            ?? text.startIndex
        let end = text.index(last.upperBound, offsetBy: contextCharacters, limitedBy: text.endIndex)
            ?? text.endIndex

        let leading = start > text.startIndex ? "…" : ""
        let trailing = end < text.endIndex ? "…" : ""
        let window = leading + String(text[start..<end]) + trailing

        /**
         Moved into the window's coordinates by counting characters, since both
         ends of this are Swift strings and the leading ellipsis is one
         character of its own.
         */
        let highlights = changes.map { change -> Range<String.Index> in
            let offset = leading.count + text.distance(from: start, to: change.lowerBound)
            let length = text.distance(from: change.lowerBound, to: change.upperBound)

            let lower = window.index(window.startIndex, offsetBy: offset)
            let upper = window.index(lower, offsetBy: length)

            return lower..<upper
        }

        return TextExcerpt(text: window, highlights: highlights)
    }

    /** Something has to bound a field with no detectable change in it. */
    private static func clip(_ text: String) -> String {
        let limit = contextCharacters * 2

        guard text.count > limit else { return text }

        return String(text.prefix(limit)) + "…"
    }
}
