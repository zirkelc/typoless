@preconcurrency import ApplicationServices
import AppKit
import Observation

/**
 Runs one correction pass, from trigger to written-back text.
 */
@MainActor
@Observable
final class CorrectionEngine {
    /**
     How long the overlay stays up at minimum.

     Without a floor, a fast pass flashes the overlay for a frame or two, which
     reads as a glitch rather than as feedback. The user should always be able
     to tell that something ran and where it ran.
     */
    private let minimumOverlayDuration: Duration = .milliseconds(350)

    /** Long enough for the pulse over the changed words to play out. */
    private let pulseDuration: Duration = .milliseconds(580)

    /** Swapped when the user changes backend, which the pipeline is indifferent to. */
    var corrector: any Corrector

    private let overlay: OverlayController
    private let preferences: Preferences
    private let escape = EscapeMonitor()

    private(set) var isRunning = false
    private(set) var lastMessage: String?
    private(set) var canRevert = false

    private var lastFix: Fix?

    /** Everything needed to put a field back the way the user left it. */
    private struct Fix {
        let element: AXUIElement
        /** The whole field before and after, so the undo is itself a minimal edit. */
        let before: String
        let after: String
    }

    init(corrector: any Corrector, overlay: OverlayController, preferences: Preferences) {
        self.corrector = corrector
        self.overlay = overlay
        self.preferences = preferences
    }

    func run() async {
        guard !isRunning else { return }

        isRunning = true
        defer {
            isRunning = false
            escape.stop()
            overlay.hide()
        }

        let target: TextTarget
        do {
            target = try TextTargetResolver.resolve(denying: preferences.deniedBundleIDs)
        } catch let error as TextTargetError {
            report(error.userMessage, log: "Could not resolve a text target: \(error)")
            return
        } catch {
            report(nil, log: "Could not resolve a text target: \(error)")
            return
        }

        overlay.show(over: target.rects)

        let original = target.selectedText
        let started = ContinuousClock.now

        let edits: [TextEdit]
        do {
            edits = try await corrections(for: original, in: target.bundleID)
        } catch is CancellationError {
            report(nil, log: "Cancelled before anything was written")
            return
        } catch {
            report("Spellbee could not correct that text.", log: "Corrector failed: \(error)")
            return
        }

        /** Give the overlay its floor before anything replaces the text under it. */
        let elapsed = ContinuousClock.now - started
        if elapsed < minimumOverlayDuration {
            try? await Task.sleep(for: minimumOverlayDuration - elapsed)
        }

        let corrected = TextDiff.apply(edits, to: original)

        guard !edits.isEmpty, corrected != original else {
            report("Nothing to fix.", log: "No changes for \(original.utf16.count) characters")
            return
        }

        /**
         Between reading the text and writing it back, the model had a second or
         two to think, and the user may have moved on. Writing now would be
         wrong in every case and destructive in one: pasting is aimed at
         whichever app is frontmost, so the correction would land in whatever
         the user switched to, over whatever they had selected there.
         */
        guard target.isStillFrontmost else {
            report(
                TextTargetError.focusMoved.userMessage,
                log: "Abandoned a correction because the frontmost app changed"
            )
            return
        }

        let fieldEdits = self.fieldEdits(from: edits, in: original, offsetBy: target.range.location)

        let strategy: TextWriter.Strategy
        do {
            strategy = try await TextWriter.apply(
                fieldEdits,
                in: target.element,
                replacing: target.range,
                with: corrected,
                isUserSelection: target.isUserSelection
            )
        } catch {
            /**
             A write can stop partway, which is the one case where a failure
             still needs an undo. Offering it costs nothing when nothing landed,
             since the record is only kept if the field actually moved.
             */
            recordForRevert(target: target)

            let message = (error as? TextWriteError)?.userMessage
            report(message, log: "Write failed: \(error)")
            return
        }

        recordForRevert(target: target)
        restoreCaret(for: target, after: fieldEdits, corrected: corrected)

        report(
            nil,
            log: "Corrected \(original.utf16.count) characters with \(fieldEdits.count) edits via \(strategy.rawValue)"
        )

        await pulse(over: fieldEdits, in: target.element)
    }

    /**
     Asks the model, with Escape wired up to give up.

     The work runs as its own task purely so it can be cancelled. Escape is a
     promise that nothing will be written, which matters most when the model is
     slow and the user has already decided they do not want this.
     */
    private func corrections(for text: String, in bundleID: String?) async throws -> [TextEdit] {
        let corrector = self.corrector
        let settings = preferences.settings(for: bundleID)

        Log.app.info(
            """
            Correcting with kinds=\(settings.allowedKinds.map(\.rawValue).sorted().joined(separator: ","), privacy: .public) \
            fullStop=\(settings.addsSentenceFinalPunctuation, privacy: .public)
            """
        )
        let work = Task { try await corrector.corrections(for: text, settings: settings) }

        escape.onPress = {
            Log.app.info("Cancelled by Escape")
            work.cancel()
        }
        escape.start()
        defer { escape.stop() }

        let result = try await work.value

        /**
         A cancelled task that finished anyway still means the user said no.
         Cancellation is cooperative, and a model already generating its reply
         has nowhere to check until it is done, so the last word has to be here.
         */
        guard !work.isCancelled else { throw CancellationError() }

        return result
    }

    /**
     Moves edits out of the text the model saw and into the field's own
     coordinates: UTF-16 offsets from the start of the whole value.
     */
    private func fieldEdits(from edits: [TextEdit], in text: String, offsetBy base: Int) -> [FieldEdit] {
        edits.map { edit in
            let start = edit.range.lowerBound.utf16Offset(in: text)
            let end = edit.range.upperBound.utf16Offset(in: text)

            return FieldEdit(
                range: CFRange(location: base + start, length: end - start),
                replacement: edit.replacement
            )
        }
    }

    /**
     Marks what changed, briefly.

     Asked of the field after the write rather than derived from the rects
     gathered before it, since the text has just moved and only the app knows
     where the corrected words ended up.
     */
    private func pulse(over edits: [FieldEdit], in element: AXUIElement) async {
        let rects = edits.landedRanges
            .compactMap(element.boundsForRange)
            .filter { $0.width > 0 && $0.height > 0 }

        guard !rects.isEmpty else { return }

        overlay.show(over: rects, style: .settled)
        try? await Task.sleep(for: pulseDuration)
    }

    /** Puts the caret back within a character or two of where the user left it. */
    private func restoreCaret(for target: TextTarget, after edits: [FieldEdit], corrected: String) {
        guard let caret = target.caret else {
            /** The user had text selected, so leave them at the end of it. */
            TextWriter.restoreCaret(
                to: target.range.location + corrected.utf16.count,
                in: target.element
            )
            return
        }

        TextWriter.restoreCaret(to: edits.caretPosition(from: caret), in: target.element)
    }

    /**
     Remembers what to undo, if anything actually changed.

     Reads what the field holds now rather than assuming the correction landed
     as intended, so a write that stopped partway can still be taken back.
     */
    private func recordForRevert(target: TextTarget) {
        guard
            let after = target.element.string(kAXValueAttribute),
            after != target.text
        else {
            lastFix = nil
            canRevert = false
            return
        }

        lastFix = Fix(element: target.element, before: target.text, after: after)
        canRevert = true
    }

    /**
     Puts back exactly what the user had written.

     The host app's own undo usually covers this, but "usually" is not good
     enough for something that edits a message the user is about to send.
     */
    func revertLast() async {
        guard let fix = lastFix else { return }

        /**
         Refuse if the user has kept typing. Undoing then would take their own
         words with it, which is a far worse surprise than a correction that
         stays.
         */
        guard let current = fix.element.string(kAXValueAttribute), current == fix.after else {
            report(
                "That text has changed since Spellbee corrected it.",
                log: "Refused to revert a field that moved on"
            )
            lastFix = nil
            canRevert = false
            return
        }

        guard let span = TextDiff.differingSpan(from: current, to: fix.before) else {
            lastFix = nil
            canRevert = false
            return
        }

        do {
            try await TextWriter.apply(
                [FieldEdit(range: span.range, replacement: span.replacement)],
                in: fix.element,
                /** The fallbacks cannot work span by span, so give them the whole value. */
                replacing: CFRange(location: 0, length: current.utf16.count),
                with: fix.before,
                isUserSelection: false
            )
            TextWriter.restoreCaret(
                to: span.range.location + span.replacement.utf16.count,
                in: fix.element
            )
        } catch {
            report("Spellbee could not undo that correction.", log: "Revert failed: \(error)")
            return
        }

        lastFix = nil
        canRevert = false
    }

    private func report(_ message: String?, log: String) {
        lastMessage = message
        Log.app.info("\(log, privacy: .public)")
    }
}
