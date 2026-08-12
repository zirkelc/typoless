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
     Set when the mouse is used between taps.

     Without this, releasing a modifier at the end of an unrelated action counts
     as a tap.
     */
    private var wasInterrupted = false

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

        add(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] _ in
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
        let isWatchedDown = flags.contains(modifier.flag)
        let others = flags.subtracting(modifier.flag)

        /** A chord is not a tap, and it ends any sequence in progress. */
        if !others.isEmpty {
            reset()
            return
        }

        defer { isDown = isWatchedDown }

        if isWatchedDown, !isDown {
            pressedAt = event.timestampDate
            keysAtPress = Self.keyDownCount
            wasInterrupted = false
            return
        }

        guard !isWatchedDown, isDown else { return }

        let releasedAt = event.timestampDate

        guard
            !wasInterrupted,
            /** A key pressed while it was held makes it a modifier, not a tap. */
            Self.keyDownCount == keysAtPress,
            let pressedAt,
            releasedAt.timeIntervalSince(pressedAt) <= holdLimit
        else {
            reset()
            return
        }

        if
            let lastTapAt,
            releasedAt.timeIntervalSince(lastTapAt) <= gapLimit,
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

    private func reset() {
        isDown = false
        pressedAt = nil
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
