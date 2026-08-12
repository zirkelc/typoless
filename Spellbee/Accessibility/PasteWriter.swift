import AppKit
import Carbon.HIToolbox

/**
 Writes text by driving the keyboard, as a last resort.

 Chromium-based apps (which is most of the Electron ones) advertise their text
 attributes as settable and then ignore every write. They do handle ordinary
 paste, because that arrives as a real keystroke rather than as an accessibility
 message, so this puts the corrected text on the pasteboard and presses ⌘V.

 The costs are real, which is why nothing reaches for this first: it borrows the
 user's clipboard, it flattens any formatting in the field, and it depends on the
 right app still being frontmost. The clipboard is put back afterwards.
 */
enum PasteWriter {
    /** Let the app finish handling the trigger keystrokes before sending more. */
    private static let settleDelay: Duration = .milliseconds(60)

    /** Time for the paste to land before the clipboard is taken back. */
    private static let pasteDelay: Duration = .milliseconds(180)

    static func replace(selectingAll: Bool, with text: String) async {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(capturing: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try? await Task.sleep(for: settleDelay)

        if selectingAll {
            press(CGKeyCode(kVK_ANSI_A))
        }
        press(CGKeyCode(kVK_ANSI_V))

        try? await Task.sleep(for: pasteDelay)

        snapshot.restore(to: pasteboard)
    }

    /** Sends one Command-modified keystroke to whichever app is frontmost. */
    private static func press(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

/**
 A copy of everything on the pasteboard, so it can be handed back untouched.

 Preserving every representation matters: a user who copied rich text or an
 image should not find a plain string in its place because a correction ran.
 */
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(capturing pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                contents[type] = item.data(forType: type)
            }
            return contents
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restored = items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(restored)
    }
}
