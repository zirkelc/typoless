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

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent("Shortcut") {
            HStack {
                Button(action: toggle) {
                    Text(isRecording ? "Press keys…" : shortcut.displayName)
                        .frame(minWidth: 120)
                        .monospacedDigit()
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : nil)

                if shortcut != .default {
                    Button("Reset") { shortcut = .default }
                }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggle() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard monitor == nil else { return }

        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            /** Modifiers on their own are held down on the way to a real key. */
            guard event.type == .keyDown else { return nil }

            if event.keyCode == kVK_Escape {
                stopRecording()
                return nil
            }

            let carbonModifiers = event.modifierFlags.carbonModifiers

            /**
             An unmodified key would fire while the user is typing in any app,
             so it is refused rather than recorded and later regretted.
             */
            guard carbonModifiers != 0 else { return nil }

            shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
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
        kVK_Escape: "⎋",
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
