import AppKit

/**
 Detects a double tap of the Command key.

 Observes events passively rather than tapping them. A double tap never needs to
 be swallowed (Command alone does nothing on its own), so there is no reason to
 take on an event tap: no Input Monitoring grant, and none of the
 disabled-by-timeout failure mode that comes with taps.

 The cost of a modifier trigger is that it cannot fire on the first tap, so
 every activation carries the double-tap window as latency. Kept as tight as it
 can be while still being comfortable to hit.
 */
@MainActor
final class ModifierTapMonitor {
    /** Longest a tap may be held and still count as a tap rather than a hold. */
    private let holdLimit: TimeInterval = 0.35

    /** Longest gap between the two taps. */
    private let gapLimit: TimeInterval = 0.4

    var onDoubleTap: (() -> Void)?

    private var monitors: [Any] = []
    private var isCommandDown = false
    private var commandDownAt: Date?
    private var lastTapAt: Date?

    /**
     Set when anything else happens between taps.

     Without this, releasing Command at the end of an unrelated shortcut counts
     as a tap, so ⌘C followed by ⌘V would fire the trigger.
     */
    private var wasInterrupted = false

    func start() {
        guard monitors.isEmpty else { return }

        add(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        add(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] _ in
            self?.wasInterrupted = true
        }
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        reset()
    }

    private func add(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(global)
        }

        /** Global monitors do not see events aimed at our own windows. */
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandIsDown = flags.contains(.command)
        let otherModifiers = flags.subtracting(.command)

        /** A chord is not a tap, and it ends any sequence in progress. */
        if !otherModifiers.isEmpty {
            reset()
            return
        }

        defer { isCommandDown = commandIsDown }

        if commandIsDown, !isCommandDown {
            commandDownAt = event.timestampDate
            wasInterrupted = false
            return
        }

        guard !commandIsDown, isCommandDown else { return }

        let releasedAt = event.timestampDate
        guard
            !wasInterrupted,
            let pressedAt = commandDownAt,
            releasedAt.timeIntervalSince(pressedAt) <= holdLimit
        else {
            reset()
            return
        }

        if let lastTapAt, releasedAt.timeIntervalSince(lastTapAt) <= gapLimit {
            reset()
            onDoubleTap?()
        } else {
            self.lastTapAt = releasedAt
        }
    }

    private func reset() {
        isCommandDown = false
        commandDownAt = nil
        lastTapAt = nil
        wasInterrupted = false
    }
}

private extension NSEvent {
    /**
     Event timestamps are seconds since boot, not wall clock, so they are
     compared against each other rather than against the current time.
     */
    var timestampDate: Date {
        Date(timeIntervalSinceReferenceDate: timestamp)
    }
}
