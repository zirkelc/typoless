import Foundation

/**
 One change in a field's own coordinates: a UTF-16 range into its whole value.

 The engine works in `String.Index` over the text it read; accessibility works
 in UTF-16 offsets over the field. This is where the two meet, so the conversion
 happens once instead of at every call site.
 */
struct FieldEdit: Sendable {
    let range: CFRange
    let replacement: String

    /** How much the field's value grows or shrinks when this lands. */
    var lengthDelta: Int { replacement.utf16.count - range.length }
}

/**
 The arithmetic of a set of changes landing in a field.

 Every one of these shifts the text after it, so a position quoted before the
 write means something else afterwards. Kept apart from the writing itself
 because it is pure, easy to get subtly wrong, and worth checking without a
 field to write into.
 */
extension Array where Element == FieldEdit {
    /** Sorted so the earliest change comes first. */
    var inTextOrder: [FieldEdit] {
        sorted { $0.range.location < $1.range.location }
    }

    /**
     Where each change ends up once they have all been applied.

     Each is displaced by however much the changes before it grew or shrank the
     text. Pure deletions are left out, since a range of no characters has
     nothing to point at.
     */
    var landedRanges: [CFRange] {
        var delta = 0
        var result: [CFRange] = []

        for edit in inTextOrder {
            let length = edit.replacement.utf16.count
            if length > 0 {
                result.append(CFRange(location: edit.range.location + delta, length: length))
            }
            delta += edit.lengthDelta
        }

        return result
    }

    /**
     Where a caret sitting at `offset` should end up.

     Only text before the caret can move it, and only by how much that text grew
     or shrank. A change inside the word the user was typing is the one case
     with no right answer, and the end of the corrected word is the least
     surprising of the wrong ones.
     */
    func caretPosition(from offset: Int) -> Int {
        var delta = 0

        for edit in inTextOrder {
            guard edit.range.location < offset else { break }

            let end = edit.range.location + edit.range.length
            guard end <= offset else {
                return edit.range.location + delta + edit.replacement.utf16.count
            }

            delta += edit.lengthDelta
        }

        return offset + delta
    }
}
