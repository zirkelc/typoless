#if DEBUG
@preconcurrency import ApplicationServices
import AppKit

/**
 Measures whether typing is observable at all, per app.

 Answers the one question the always-on idea turns on: when someone types, does
 the app tell the accessibility API about it? The design is sound in the
 abstract and worthless in an app that stays silent, and which apps those are is
 a fact about other people's software that cannot be reasoned out from here.

 Three outcomes are worth telling apart, and only the third is fatal:

 - the app refuses the observer outright, so nothing can be built on it
 - the observer attaches and never fires, which looks identical from inside the
   app and is just as unusable
 - the observer fires, and the ratio of notifications to keystrokes says how
   much of the typing was actually seen

 Counts only. No text is read, kept or logged, which is also why the numbers are
 approximate: keystrokes are attributed to whichever app was frontmost when the
 counter moved, so a shortcut aimed at one app while another is switching lands
 in the wrong column. Good enough for a ratio, not for arithmetic.

 Debug only, and deliberately throwaway.
 */
@MainActor
final class TypingObserver {
    struct Sample: Codable {
        /** Key presses while this app was frontmost, from the system's own counter. */
        var keyDowns = 0
        /** The notification that matters: the field's contents changed. */
        var valueChanges = 0
        /** Cheaper to emit, and some apps send only this one. */
        var selectionChanges = 0
        /** Times a text-shaped element took focus, so silence can be told from disuse. */
        var textFocuses = 0
        /** The app refused to be observed, which is the fatal case. */
        var attachFailures = 0
    }

    private(set) var samples: [String: Sample] = [:]
    private(set) var isRunning = false

    /** Where a day-long run survives the relaunches a day will contain. */
    private static var storeURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Spellbee/typing-observation.json")
    }

    private var observers: [pid_t: AXObserver] = [:]
    private var watched: [pid_t: AXUIElement] = [:]
    private var frontmost: (pid: pid_t, bundleID: String)?
    private var lastKeyCount = 0
    private var ticks = 0
    private var timer: Timer?

    init() {
        samples = Self.load()
    }

    func start() {
        guard !isRunning else { return }

        /**
         Attaching without the accessibility grant fails for every app and is
         recorded as the app refusing to be observed, which the report calls the
         fatal case. That would be a lie about someone else's software.
         */
        guard AXIsProcessTrusted() else {
            Log.app.error("Typing observation needs accessibility access")
            return
        }

        isRunning = true
        lastKeyCount = Self.systemKeyDownCount

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        /**
         Without this the table grows one dead entry per app for the life of the
         run, and worse: macOS reuses process ids, so a later app inheriting one
         is met with the dead app's observer, fails to attach every time it is
         activated, and is permanently recorded as refusing to be observed.
         */
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        /**
         Polled rather than observed, because counting keystrokes properly needs
         Input Monitoring and this spike is not worth a permission prompt. The
         system keeps a running total that anyone may read.
         */
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }

                self.sampleKeystrokes()

                /**
                 Written out as it goes, so a run can be read while it is still
                 going and survives the app being killed rather than stopped.
                 */
                self.ticks += 1
                if self.ticks % 5 == 0 { self.save() }
            }
        }

        attachToFrontmost()

        Log.app.info("Typing observation started")
    }

    func stop() {
        guard isRunning else { return }

        isRunning = false

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        timer?.invalidate()
        timer = nil

        sampleKeystrokes()

        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        observers.removeAll()
        watched.removeAll()
        frontmost = nil

        save()
        Log.app.info("Typing observation stopped")
    }

    func reset() {
        samples = [:]
        save()
    }

    // MARK: Keystrokes

    /** Needs no permission, unlike watching the events themselves. */
    private static var systemKeyDownCount: Int {
        Int(CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown))
    }

    private func sampleKeystrokes() {
        let count = Self.systemKeyDownCount
        defer { lastKeyCount = count }

        guard let bundleID = frontmost?.bundleID, count > lastKeyCount else { return }

        samples[bundleID, default: Sample()].keyDowns += count - lastKeyCount
    }

    // MARK: Attaching

    @objc private func appTerminated(_ note: Notification) {
        guard
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
            return
        }

        let pid = app.processIdentifier

        if let observer = observers[pid] {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        observers[pid] = nil
        watched[pid] = nil
    }

    @objc private func frontmostChanged() {
        /** Attribute what was typed before the switch to the app it was typed in. */
        sampleKeystrokes()
        attachToFrontmost()
    }

    private func attachToFrontmost() {
        guard
            let app = NSWorkspace.shared.frontmostApplication,
            let bundleID = app.bundleIdentifier
        else {
            return
        }

        let pid = app.processIdentifier
        frontmost = (pid, bundleID)

        guard observers[pid] == nil else {
            watchFocusedElement(of: pid, bundleID: bundleID)
            return
        }

        var observer: AXObserver?
        let created = AXObserverCreate(pid, typingObserverCallback, &observer)

        guard created == .success, let observer else {
            samples[bundleID, default: Sample()].attachFailures += 1
            Log.app.info("Could not observe \(bundleID, privacy: .public): \(created.rawValue, privacy: .public)")
            return
        }

        /**
         `GetMain` rather than `GetCurrent`, so adding and removing provably
         name the same run loop. The source is retained by the run loop but the
         observer is not, so dropping the observer without removing the source
         leaves the run loop calling into freed memory.
         */
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observers[pid] = observer

        /** Focus moves constantly, so the element being watched has to move with it. */
        let application = AXUIElementCreateApplication(pid)
        let added = AXObserverAddNotification(
            observer,
            application,
            kAXFocusedUIElementChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )

        if added != .success {
            samples[bundleID, default: Sample()].attachFailures += 1
            Log.app.info("No focus notifications from \(bundleID, privacy: .public)")
        }

        watchFocusedElement(of: pid, bundleID: bundleID)
    }

    private func watchFocusedElement(of pid: pid_t, bundleID: String) {
        guard
            let observer = observers[pid],
            let focused = AXUIElementCreateApplication(pid).element(kAXFocusedUIElementAttribute)
        else {
            return
        }

        if let previous = watched[pid] {
            AXObserverRemoveNotification(observer, previous, kAXValueChangedNotification as CFString)
            AXObserverRemoveNotification(observer, previous, kAXSelectedTextChangedNotification as CFString)
        }

        watched[pid] = focused

        /**
         Only text-shaped elements are interesting, and counting them separately
         is what distinguishes "this app never reports typing" from "nobody typed
         into it while this was running".
         */
        let role = focused.string(kAXRoleAttribute) ?? ""
        let isTextual = role == kAXTextFieldRole || role == kAXTextAreaRole
            || focused.isSettable(kAXSelectedTextAttribute)

        guard isTextual else { return }

        samples[bundleID, default: Sample()].textFocuses += 1

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        for notification in [kAXValueChangedNotification, kAXSelectedTextChangedNotification] {
            let added = AXObserverAddNotification(observer, focused, notification as CFString, refcon)

            if added != .success {
                samples[bundleID, default: Sample()].attachFailures += 1
            }
        }
    }

    // MARK: Counting

    fileprivate func record(_ notification: String, from element: AXUIElement) {
        /**
         Notifications are never unregistered when an app goes to the background,
         so every app ever activated keeps firing into here. Crediting those to
         whoever is frontmost inflated the foreground app's count with the
         background app's events, which is precisely the number this whole
         exercise exists to measure.
         */
        var source: pid_t = 0

        guard
            AXUIElementGetPid(element, &source) == .success,
            let (pid, bundleID) = frontmost,
            source == pid
        else {
            return
        }

        if notification == kAXFocusedUIElementChangedNotification as String {
            watchFocusedElement(of: pid, bundleID: bundleID)
            return
        }

        switch notification {
        case kAXValueChangedNotification as String:
            /** Only the first, so the wiring can be confirmed without a day of noise. */
            if samples[bundleID]?.valueChanges ?? 0 == 0 {
                Log.app.info("First value change from \(bundleID, privacy: .public)")
            }
            samples[bundleID, default: Sample()].valueChanges += 1
        case kAXSelectedTextChangedNotification as String:
            samples[bundleID, default: Sample()].selectionChanges += 1
        default:
            break
        }
    }

    // MARK: Reporting

    /**
     The table the decision turns on, widest coverage first.

     Coverage is notifications over keystrokes. It will not reach 100%: shortcuts
     and navigation keys are counted as keystrokes and change no text. What
     matters is the shape, and especially the apps sitting near zero with
     keystrokes and text focuses to their name.
     */
    func report() -> String {
        sampleKeystrokes()
        save()

        let rows = samples
            .filter { $0.value.keyDowns > 0 || $0.value.attachFailures > 0 }
            .sorted { coverage(of: $0.value) > coverage(of: $1.value) }

        guard !rows.isEmpty else { return "Nothing observed yet." }

        /**
         Padded in Swift, not in the format string: width specifiers are ignored
         for `%@`, so every numeric column shifted with the length of the bundle
         id and the table could not line up however monospaced the font was.
         */
        func column(_ text: String, _ width: Int) -> String {
            text.count >= width
                ? String(text.prefix(width - 1)) + " "
                : text.padding(toLength: width, withPad: " ", startingAt: 0)
        }

        func number(_ value: Int, _ width: Int) -> String {
            String(repeating: " ", count: max(0, width - String(value).count)) + String(value)
        }

        var lines = [
            column("app", 34)
                + ["keys", "value", "select", "focus", "fail", "cover"]
                    .map { column($0, 8) }
                    .joined()
        ]

        for (bundleID, sample) in rows {
            lines.append(
                column(bundleID, 34)
                    + number(sample.keyDowns, 8)
                    + number(sample.valueChanges, 8)
                    + number(sample.selectionChanges, 8)
                    + number(sample.textFocuses, 8)
                    + number(sample.attachFailures, 8)
                    + String(repeating: " ", count: 3)
                    + percentage(coverage(of: sample))
            )
        }

        return lines.joined(separator: "\n")
    }

    private func coverage(of sample: Sample) -> Double {
        guard sample.keyDowns > 0 else { return 0 }

        return Double(sample.valueChanges) / Double(sample.keyDowns)
    }

    private func percentage(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    // MARK: Storage

    private func save() {
        let url = Self.storeURL

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            /** Atomic, because the point of writing as it goes is to survive a kill. */
            try JSONEncoder().encode(samples).write(to: url, options: .atomic)
        } catch {
            Log.app.error("Could not save typing observations: \(String(describing: error), privacy: .public)")
        }
    }

    private static func load() -> [String: Sample] {
        guard let data = try? Data(contentsOf: storeURL) else { return [:] }

        do {
            return try JSONDecoder().decode([String: Sample].self, from: data)
        } catch {
            /** Silently returning nothing here would discard days of measurement unremarked. */
            Log.app.error("Could not read the saved run: \(String(describing: error), privacy: .public)")
            return [:]
        }
    }
}

/**
 The C callback, which cannot capture, so the observer arrives as a raw pointer.

 Runs on the main run loop, since that is the one the observer's source was
 added to, which is what makes stepping onto the main actor here sound.
 */
private func typingObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }

    let name = notification as String
    /** Carried across as a number, since a raw pointer is not sendable. */
    let address = UInt(bitPattern: refcon)

    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }

        Unmanaged<TypingObserver>.fromOpaque(pointer)
            .takeUnretainedValue()
            .record(name, from: element)
    }
}
#endif
