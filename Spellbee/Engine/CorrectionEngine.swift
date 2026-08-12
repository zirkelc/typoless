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

    /** Swapped when the user changes backend, which the pipeline is indifferent to. */
    var corrector: any Corrector

    private let overlay: OverlayController

    private(set) var isRunning = false
    private(set) var lastMessage: String?
    private(set) var canRevert = false

    private var lastFix: Fix?

    /** Everything needed to put a field back the way the user left it. */
    private struct Fix {
        let element: AXUIElement
        /** Where the replacement text now sits, so it can be selected again. */
        let range: CFRange
        let originalText: String
    }

    init(corrector: any Corrector, overlay: OverlayController) {
        self.corrector = corrector
        self.overlay = overlay
    }

    func run() async {
        guard !isRunning else { return }

        isRunning = true
        defer {
            isRunning = false
            overlay.hide()
        }

        let target: TextTarget
        do {
            target = try TextTargetResolver.resolve()
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

        let corrected: String
        do {
            corrected = try await corrector.correct(original)
        } catch {
            report("Spellbee could not correct that text.", log: "Corrector failed: \(error)")
            return
        }

        /** Give the overlay its floor before anything replaces the text under it. */
        let elapsed = ContinuousClock.now - started
        if elapsed < minimumOverlayDuration {
            try? await Task.sleep(for: minimumOverlayDuration - elapsed)
        }

        guard corrected != original else {
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

        let strategy: TextWriter.Strategy
        do {
            strategy = try await TextWriter.replace(
                range: target.range,
                with: corrected,
                in: target.element,
                isUserSelection: target.isUserSelection
            )
        } catch let error as TextWriteError {
            report(error.userMessage, log: "Write failed: \(error)")
            return
        } catch {
            report(nil, log: "Write failed: \(error)")
            return
        }

        let newRange = CFRange(location: target.range.location, length: corrected.utf16.count)
        lastFix = Fix(element: target.element, range: newRange, originalText: original)
        canRevert = true

        TextWriter.restoreCaret(to: newRange.location + newRange.length, in: target.element)

        report(nil, log: "Corrected \(original.utf16.count) characters via \(strategy.rawValue)")
    }

    /**
     Puts back exactly what the user had written.

     The host app's own undo usually covers this, but "usually" is not good
     enough for something that edits a message the user is about to send.
     */
    func revertLast() async {
        guard let fix = lastFix else { return }

        do {
            try await TextWriter.replace(
                range: fix.range,
                with: fix.originalText,
                in: fix.element,
                isUserSelection: false
            )
            TextWriter.restoreCaret(
                to: fix.range.location + fix.originalText.utf16.count,
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
