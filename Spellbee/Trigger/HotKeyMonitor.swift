import AppKit
import Carbon.HIToolbox

/**
 The conventional global shortcut that triggers a correction.

 The shortcut is fixed for now. The recorder UI arrives with settings.
 */
@MainActor
final class HotKeyMonitor {
    /**
     Default shortcut: ⌃⌥⌘Space.

     Space with fewer modifiers is crowded: plain ⌥Space is commonly taken by
     launchers, ⌃⌘Space is the emoji picker, and ⌥⌘Space is the system's Finder
     search window. That last one was the original default here and it never
     worked: registration succeeded, the correction started, and Finder came
     forward anyway, so the guard against the frontmost app changing threw every
     result away. A shortcut can be claimed and still lose.

     Three modifiers is awkward to type, which matters less than it looks: the
     double tap is the everyday trigger and this is the fallback for when it
     misfires. A recorder in settings replaces this.
     */
    static let defaultKeyCode = UInt32(kVK_Space)
    static let defaultModifiers = UInt32(controlKey | optionKey | cmdKey)

    var onFire: (() -> Void)?

    private let hotKey = CarbonHotKey(identifier: HotKeyIdentifier.correct)

    func start(keyCode: UInt32 = defaultKeyCode, modifiers: UInt32 = defaultModifiers) {
        hotKey.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.onFire?()
        }
    }

    func stop() {
        hotKey.unregister()
    }
}

/** Keeps the app's shortcuts apart, since Carbon offers every one to every handler. */
enum HotKeyIdentifier {
    static let correct: UInt32 = 1
    static let cancel: UInt32 = 2
}
