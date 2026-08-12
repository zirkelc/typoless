@preconcurrency import ApplicationServices
import AppKit

/**
 Writes corrections back into a field.

 Prefers to touch only the words that changed. Replacing the whole field is the
 obvious implementation and the wrong one: a Slack composer holds mentions and
 links as more than characters, and writing a plain string over the top of them
 flattens every one. Writing each changed range on its own leaves everything the
 correction did not touch exactly as the user left it, formatting included.

 A successful `AXError` means the app accepted the message, not that it acted on
 it. Plenty of fields return success from setting an attribute and then leave
 their contents exactly as they were, so every write here is confirmed by
 reading the value back. Without that the app reports corrections it never made.
 */
enum TextWriter {
    /** How the text actually got written, which differs in what it costs. */
    enum Strategy: String {
        /**
         Each changed range replaced on its own. The good path: rich text, links
         and mentions survive, and the edits land in the host app's undo stack.
         */
        case edits
        /**
         Overwrite the whole value. Works where replacing a selection is
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

    /**
     Applies a set of changes to a field, by whichever means the field accepts.

     - Parameters:
       - edits: The changes, in the field's own UTF-16 coordinates.
       - range: The span being corrected, used only by the fallbacks that cannot
         work edit by edit.
       - corrected: That span with every change already made, for the same
         fallbacks.
     */
    @discardableResult
    static func apply(
        _ edits: [FieldEdit],
        in element: AXUIElement,
        replacing range: CFRange,
        with corrected: String,
        isUserSelection: Bool
    ) async throws -> Strategy {
        guard !edits.isEmpty else { throw TextWriteError.ineffective }

        let before = element.string(kAXValueAttribute)
        var attemptedEdits = false

        if element.isSettable(kAXSelectedTextAttribute) {
            attemptedEdits = true

            if let applied = try await applyIndividually(edits, in: element) {
                Log.app.info(
                    "Wrote \(applied, privacy: .public) of \(edits.count, privacy: .public) edits in place"
                )
                return .edits
            }

            Log.app.info("Field ignored an in-place edit, falling back")
        }

        /**
         Trying the edits moved the selection to whichever one was attempted
         last. Both fallbacks below assume the user's own selection is still
         where it was, and pasting into the wrong one would replace text the
         user never offered.
         */
        if attemptedEdits {
            element.setRange(kAXSelectedTextRangeAttribute, to: range)
        }

        if element.isSettable(kAXValueAttribute), let before {
            guard let spliced = splice(corrected, into: before, at: range) else {
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
        await PasteWriter.replace(selectingAll: !isUserSelection, with: corrected)

        if await didChange(from: before, in: element) {
            return .paste
        }

        throw TextWriteError.ineffective
    }

    /**
     Replaces each changed range on its own, back to front.

     Working backwards keeps every remaining range valid, since an edit only
     ever shifts the text after it.

     Returns nil when the field ignored the very first attempt, which means
     nothing was written and a fallback is free to start from a clean field.
     Once one edit has landed there is no going back, so a later refusal is
     reported and the rest carry on: they sit at lower offsets and are
     unaffected by the one that failed.
     */
    private static func applyIndividually(_ edits: [FieldEdit], in element: AXUIElement) async throws -> Int? {
        #if DEBUG
        /**
         Forces the fallback, so the damage this tier avoids can be seen rather
         than argued about. Correcting a styled TextEdit document with
         `SPELLBEE_FORCE_WHOLE_VALUE=1` set returns every word to the default
         colour and size; without it the styling survives untouched.
         */
        if ProcessInfo.processInfo.environment["SPELLBEE_FORCE_WHOLE_VALUE"] != nil {
            Log.app.info("Skipping in-place edits because the environment asks for the fallback")
            return nil
        }
        #endif

        guard var expected = element.string(kAXValueAttribute) else { return nil }

        var applied = 0

        for edit in edits.inTextOrder.reversed() {
            guard let next = splice(edit.replacement, into: expected, at: edit.range) else {
                Log.app.error("Skipped an edit whose range does not fit the field")
                continue
            }

            element.setRange(kAXSelectedTextRangeAttribute, to: edit.range)
            element.set(kAXSelectedTextAttribute, to: edit.replacement as CFString)

            if await settles(on: next, in: element) {
                expected = next
                applied += 1
                continue
            }

            /**
             Two very different failures wear the same face here. A field that
             still holds what it held before simply ignored the write, and the
             remaining edits are unharmed. A field holding anything else has
             done something this code does not model, and writing further edits
             into text whose shape is now unknown is how good messages get
             mangled.
             */
            guard element.string(kAXValueAttribute) == expected else {
                Log.app.error("A field changed unexpectedly mid-write, stopping")
                throw TextWriteError.diverged
            }

            guard applied > 0 else { return nil }
            Log.app.info("A field ignored one edit, keeping the rest")
        }

        return applied > 0 ? applied : nil
    }

    /**
     Puts the caret back where the user left it. Cheap to get wrong and very
     annoying when it is.
     */
    static func restoreCaret(to offset: Int, in element: AXUIElement) {
        element.setRange(kAXSelectedTextRangeAttribute, to: CFRange(location: offset, length: 0))
    }

    /**
     Waits for a field to hold exactly the given text.

     The first check happens before any waiting, so a field that keeps up costs
     one read and nothing else. Only a field that lags, or one that is quietly
     refusing, pays the timeout.
     */
    private static func settles(on expected: String, in element: AXUIElement) async -> Bool {
        var waited: Duration = .zero

        while true {
            if element.string(kAXValueAttribute) == expected { return true }
            guard waited < confirmationTimeout else { return false }

            try? await Task.sleep(for: confirmationInterval)
            waited += confirmationInterval
        }
    }

    /**
     Whether a field moved at all, for the paste path where the exact result is
     not ours to predict: an app may normalise what it receives from the
     clipboard, so only the fact of a change can be checked.
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

    /** The field's contents moved in a way this code cannot account for. */
    case diverged

    var userMessage: String {
        switch self {
        case .ineffective:
            return "Spellbee could not write the correction back into that field."
        case .diverged:
            return "Spellbee stopped because that field changed while it was being corrected."
        }
    }
}
