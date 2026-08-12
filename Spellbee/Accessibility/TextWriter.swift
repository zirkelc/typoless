@preconcurrency import ApplicationServices
import AppKit

/**
 Writes corrected text back into a field.

 A successful `AXError` means the app accepted the message, not that it acted on
 it. Plenty of fields return success from setting an attribute and then leave
 their contents exactly as they were, so every write here is confirmed by
 reading the value back. Without that the app reports corrections it never made.
 */
enum TextWriter {
    /** How the text actually got written, which differs in what it costs. */
    enum Strategy: String {
        /**
         Replace the user's selection. The good path: rich text, links and
         mentions survive, and the edit lands in the host app's undo stack.
         */
        case selection
        /**
         Overwrite the whole value. Works where selection replacement is
         ignored, at the cost of flattening any formatting in the field.
         */
        case wholeValue
        /**
         Paste it. The only thing that reaches apps which ignore accessibility
         writes altogether, and the most invasive: it borrows the clipboard and
         flattens formatting.
         */
        case paste
    }

    /** Longest we wait for a field to catch up before deciding a write did nothing. */
    private static let confirmationTimeout: Duration = .milliseconds(200)
    private static let confirmationInterval: Duration = .milliseconds(20)

    @discardableResult
    static func replace(
        range: CFRange,
        with replacement: String,
        in element: AXUIElement,
        isUserSelection: Bool
    ) async throws -> Strategy {
        let before = element.string(kAXValueAttribute)

        if element.isSettable(kAXSelectedTextAttribute) {
            element.setRange(kAXSelectedTextRangeAttribute, to: range)
            element.set(kAXSelectedTextAttribute, to: replacement as CFString)

            if await didChange(from: before, in: element) {
                return .selection
            }
            Log.app.info("Selection write was accepted but changed nothing, falling back")
        }

        if element.isSettable(kAXValueAttribute), let before {
            guard let spliced = splice(replacement, into: before, at: range) else {
                throw TextWriteError.ineffective
            }

            element.set(kAXValueAttribute, to: spliced as CFString)

            if await didChange(from: before, in: element) {
                return .wholeValue
            }
            Log.app.info("Whole-value write was accepted but changed nothing, falling back")
        }

        /**
         The user's own selection is already in place, so only a whole-field
         pass needs to select first.
         */
        await PasteWriter.replace(selectingAll: !isUserSelection, with: replacement)

        if await didChange(from: before, in: element) {
            return .paste
        }

        throw TextWriteError.ineffective
    }

    /**
     Puts the caret back where the user left it, adjusted for how much the text
     grew or shrank ahead of it. Cheap to get wrong and very annoying when it is.
     */
    static func restoreCaret(to offset: Int, in element: AXUIElement) {
        element.setRange(kAXSelectedTextRangeAttribute, to: CFRange(location: offset, length: 0))
    }

    /**
     Some fields update on their own schedule rather than by the time the set
     call returns, so give them a moment before concluding nothing happened.
     */
    private static func didChange(from before: String?, in element: AXUIElement) async -> Bool {
        var waited: Duration = .zero

        while waited < confirmationTimeout {
            if element.string(kAXValueAttribute) != before { return true }
            try? await Task.sleep(for: confirmationInterval)
            waited += confirmationInterval
        }

        return element.string(kAXValueAttribute) != before
    }

    private static func splice(_ replacement: String, into text: String, at range: CFRange) -> String? {
        let nsRange = NSRange(location: range.location, length: range.length)
        guard let swiftRange = Range(nsRange, in: text) else { return nil }

        return text.replacingCharacters(in: swiftRange, with: replacement)
    }
}

enum TextWriteError: Error {
    /** The field took the write and kept its old contents. */
    case ineffective

    var userMessage: String {
        "Spellbee could not write the correction back into that field."
    }
}
