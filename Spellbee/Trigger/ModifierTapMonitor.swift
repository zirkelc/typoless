import AppKit

/**
 Detects a double tap of a modifier key.

 Observes events passively rather than tapping them. A double tap never needs to
 be swallowed (a modifier alone does nothing on its own), so there is no reason
 to take on an event tap: no Input Monitoring grant, and none of the
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

    /** Which key to watch. Changing it while running rebinds immediately. */
    var modifier: TapModifier = .command {
        didSet { reset() }
    }

    private var monitors: [Any] = []
    private var isDown = false
    private var pressedAt: Date?
    private var lastTapAt: Date?

    /**
     When the mouse was last used, so an interruption can be placed in time.

     Without this, releasing a modifier at the end of an unrelated action counts
     as a tap. A plain flag could not express *when*, so clearing it on each
     press guarded only the inside of one press and release, which is not where
     the risk is, and not clearing it made every click eat the following tap.
     */
    private var interruptedAt: Date?

    /**
     How many keys the session had seen at each point of interest.

     Typing is what separates "tapped Shift twice" from "wrote two capital
     letters", and this app cannot see key presses: a global `NSEvent` keyDown
     monitor never fires without Input Monitoring, silently, so the guard that
     used to rely on one was doing nothing at all. The session's own keystroke
     counter needs no permission and answers the only question being asked,
     which is whether any key was pressed in between.
     */
    private var keysAtPress: UInt32 = 0
    private var keysAtLastTap: UInt32 = 0

    func start() {
        guard monitors.isEmpty else { return }

        add(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        /**
         Scrolling is deliberately not watched. It woke this process on every
         scroll event anywhere on the system to set a flag that only matters
         while a modifier is held, and scrolling with a modifier down is an
         ordinary zoom rather than a sign the user has moved on.
         */
        add(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.interruptedAt = event.timestampDate
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

    /**
     The modifiers a tap can be made of.

     Deliberately not `deviceIndependentFlagsMask`, which also carries Caps
     Lock, Fn, the numeric keypad and Help. Caps Lock is the one that mattered:
     while it is on it rides along on every event, so the chord test below saw a
     second modifier that the user had not pressed and abandoned every sequence.
     The trigger simply stopped working, silently, until Caps Lock went off.
     */
    private static let tappableModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /** Set while a chord is being unwound, so its tail is not read as a tap. */
    private var isChording = false

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.tappableModifiers)
        let isWatchedDown = flags.contains(modifier.flag)
        let others = flags.subtracting(modifier.flag)

        /** A chord is not a tap, and it ends any sequence in progress. */
        if !others.isEmpty {
            reset()
            /**
             Held until every modifier is off again. Without it, releasing the
             extra modifier while still holding the watched one looked exactly
             like a fresh press, so letting go afterwards recorded a tap the
             user never made, and the next real tap fired a correction they were
             not aiming at. No key is pressed in that sequence, so the keystroke
             counter cannot catch it either.
             */
            isChording = true
            return
        }

        if isChording {
            guard flags.isEmpty else { return }

            isChording = false
        }

        defer { isDown = isWatchedDown }

        if isWatchedDown, !isDown {
            pressedAt = event.timestampDate
            keysAtPress = Self.keyDownCount
            return
        }

        guard !isWatchedDown, isDown else { return }

        let releasedAt = event.timestampDate

        guard
            let pressedAt,
            /** A click while it was held means the modifier was part of that click. */
            !wasInterrupted(since: pressedAt),
            /** A key pressed while it was held makes it a modifier, not a tap. */
            Self.keyDownCount == keysAtPress,
            releasedAt.timeIntervalSince(pressedAt) <= holdLimit
        else {
            reset()
            return
        }

        if
            let lastTapAt,
            releasedAt.timeIntervalSince(lastTapAt) <= gapLimit,
            /** A click between the two taps means the user moved on in between. */
            !wasInterrupted(since: lastTapAt),
            /** Typing between the taps means this was writing, not a trigger. */
            Self.keyDownCount == keysAtLastTap
        {
            reset()
            onDoubleTap?()
        } else {
            self.lastTapAt = releasedAt
            keysAtLastTap = Self.keyDownCount
        }
    }

    /** Keys pressed in this login session, counted by the window server. */
    private static var keyDownCount: UInt32 {
        UInt32(CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown))
    }

    private func wasInterrupted(since moment: Date) -> Bool {
        guard let interruptedAt else { return false }

        return interruptedAt >= moment
    }

    private func reset() {
        isDown = false
        pressedAt = nil
        lastTapAt = nil
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
