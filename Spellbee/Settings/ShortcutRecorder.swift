import Carbon.HIToolbox
import SwiftUI

/**
 Captures the next key combination the user presses.

 Records rather than offering a list, because the shortcut has to be one this
 machine can actually deliver: which combinations are free depends on the
 system's own shortcuts, on the keyboard layout, and on whatever else the user
 has running. Letting them press it is the only honest way to find out.

 While recording, a local monitor swallows every key event, so typing ⌘W to
 record it does not close the window instead.
 */
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut

    /**
     Whether a key with no modifiers may be recorded.

     False for a trigger, since an unmodified key would fire while the user is
     typing in any app. True for the key that abandons a correction, which is
     claimed only while one is running and is a bare Escape by default.
     */
    var allowsUnmodifiedKeys = false

    /** What to go back to, which is not the same key for both recorders. */
    var fallback: Shortcut = .default

    @State private var isRecording = false

    /** Identifies this recorder to the shared listener, so it knows whose turn ended. */
    @State private var token = UUID()

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Text(isRecording ? "Press keys…" : shortcut.displayName)
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)

            if isRecording {
                Text(allowsUnmodifiedKeys ? "click again to cancel" : "Esc to cancel")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if shortcut != fallback {
                Button("Reset") { shortcut = fallback }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggle() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard !isRecording else { return }

        isRecording = true

        ShortcutListener.shared.start(for: token, onCancel: { isRecording = false }) { event in
            /** Modifiers on their own are held down on the way to a real key. */
            guard event.type == .keyDown else { return nil }

            /**
             Escape backs out of recording, except where Escape is itself a
             legitimate answer, in which case the button is the way out.
             */
            if event.keyCode == kVK_Escape, !allowsUnmodifiedKeys {
                stopRecording()
                return nil
            }

            let carbonModifiers = event.modifierFlags.carbonModifiers

            guard allowsUnmodifiedKeys || carbonModifiers != 0 else { return nil }

            shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        ShortcutListener.shared.stop(for: token)
    }
}

/**
 The one key listener a recorder may have, shared by all of them.

 Two problems, both from every recorder owning its own monitor. A monitor that
 swallows every key press was torn down by SwiftUI telling the view it had
 disappeared, which never happens for a window that is kept rather than
 released: closing the settings window mid-recording left it installed, and from
 then on Spellbee ate every key in its own windows, including the ⌘W that would
 have closed the window and the ⌘Q that would have quit. And nothing stopped two
 recorders listening at once, in which case only the first-installed one sees
 the key, so the shortcut lands on the wrong setting and the other stays armed.

 One listener, owned here, ended by whoever closes the window.
 */
@MainActor
final class ShortcutListener {
    static let shared = ShortcutListener()

    private var monitor: Any?
    private var owner: UUID?
    private var onCancel: (() -> Void)?

    private init() {}

    func start(for token: UUID, onCancel: @escaping () -> Void, handler: @escaping (NSEvent) -> NSEvent?) {
        /** Whoever was listening has been interrupted, and needs to know. */
        stopAll()

        owner = token
        self.onCancel = onCancel
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: handler)
    }

    func stop(for token: UUID) {
        guard owner == token else { return }

        remove()
    }

    /** Ends any recording in progress, whoever owns it. */
    func stopAll() {
        let interrupted = onCancel

        remove()
        interrupted?()
    }

    private func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        owner = nil
        onCancel = nil
    }
}

extension Shortcut {
    /** How the shortcut is written on a Mac: modifiers in order, then the key. */
    var displayName: String {
        var result = ""

        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }

        return result + Self.name(forKeyCode: keyCode)
    }

    /**
     The character a key produces on the current layout.

     Asked of the keyboard rather than hard-coded, so a German layout shows the
     key the user will actually press. Keys that produce no character, and those
     whose character is unhelpful to print, are named instead.
     */
    private static func name(forKeyCode keyCode: UInt32) -> String {
        if let special = specialKeyNames[Int(keyCode)] { return special }

        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return "Key \(keyCode)"
        }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }

            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return "Key \(keyCode)" }

        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "Escape",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

private extension NSEvent.ModifierFlags {
    /** The Carbon bit field `RegisterEventHotKey` wants, which is not the Cocoa one. */
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0

        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        if contains(.command) { result |= UInt32(cmdKey) }

        return result
    }
}
