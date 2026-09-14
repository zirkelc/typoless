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

    /**
     Presses the keys and hands the clipboard back once the paste has landed.

     `settled` is polled by the caller, which is the only party that can tell
     whether the field took the text. Restoring on a fixed timer instead was a
     race the app could not win: the paste is asynchronous in the target
     application, so a busy app could service the ⌘V *after* the clipboard had
     been put back, pasting whatever the user had copied over the selection the
     ⌘A had just made. Returns whether the paste was confirmed.
     */
    @discardableResult
    static func replace(
        selectingAll: Bool,
        with text: String,
        settled: () async -> Bool
    ) async -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(capturing: pasteboard)

        pasteboard.clearContents()

        /** No point pressing anything if the text never reached the pasteboard. */
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(to: pasteboard)
            Log.app.error("Could not put the correction on the pasteboard")
            return false
        }

        try? await Task.sleep(for: settleDelay)

        if selectingAll {
            press(CGKeyCode(kVK_ANSI_A))
        }
        press(CGKeyCode(kVK_ANSI_V))

        let landed = await settled()

        snapshot.restore(to: pasteboard)

        return landed
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

    /**
     Some representations cannot be copied at all: file promises and another
     app's deferred rich content are handed over lazily, so `data(forType:)`
     returns nil and assigning that nil to the dictionary *removes the key*.
     Those types were disappearing silently, which is the one thing a snapshot
     must not do, so anything unreadable is now said out loud.
     */
    init(capturing pasteboard: NSPasteboard) {
        var missed: [NSPasteboard.PasteboardType] = []

        items = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]

            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                } else {
                    missed.append(type)
                }
            }

            return contents
        }

        if !missed.isEmpty {
            Log.app.info(
                "Could not preserve \(missed.count, privacy: .public) clipboard representations"
            )
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
