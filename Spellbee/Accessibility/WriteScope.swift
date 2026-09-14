import Foundation

/**
 How much of a field a write is entitled to touch.

 Split out of the writer, which cannot be compiled without AppKit and the
 accessibility API, so the one rule that decides whether a correction is allowed
 to flatten someone's formatting is a plain function of a range and a string.
 */
enum WriteScope {
    /**
     Whether rewriting the whole field is proportionate to what is being fixed.

     Setting a field's value hands it a plain string, so everything it held
     beyond bare characters is lost: links, mentions, emphasis, list structure.
     That is an acceptable price when the field *is* the thing being corrected,
     and a terrible one for landing a three-character fix inside eight hundred
     characters of someone's formatted writing, which is what it did before this
     check existed.

     There is no ratio to tune. Either the span being corrected is the whole
     field, in which case nothing outside it can be lost, or it is not. Where it
     is not, pasting is the better fallback despite borrowing the clipboard,
     because it replaces the selection and leaves the rest of the field alone.
     */
    static func coversWholeField(_ range: CFRange, of text: String) -> Bool {
        range.location == 0 && range.length >= text.utf16.count
    }
}
