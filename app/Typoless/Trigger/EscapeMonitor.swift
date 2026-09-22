import AppKit
import Carbon.HIToolbox

/**
 Claims the cancel key while a correction is running.

 Registered only for the second or two a pass takes, rather than for the life of
 the app, so Escape means what it always means everywhere else the rest of the
 time.

 Claimed rather than observed, which was not the first attempt. A global
 `NSEvent` keyDown monitor looked right and never fired once, with accessibility
 already granted and the trigger's own modifier monitor working from the same
 process. Whatever gates key presses there, it is not something this app has,
 and it fails silently rather than reporting anything.

 Registering the key needs no permission at all, and has the better behaviour
 anyway, since it stops Escape from also reaching the app underneath. During
 those couple of seconds Escape means "stop correcting" and nothing else, which
 is exactly what someone pressing it wants.
 */
@MainActor
final class EscapeMonitor {
    var onPress: (() -> Void)?

    private let hotKey = CarbonHotKey(identifier: HotKeyIdentifier.cancel)

    func start(_ shortcut: Shortcut = .cancel) {
        hotKey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            Log.app.info("Cancel key pressed")
            self?.onPress?()
        }
    }

    func stop() {
        hotKey.unregister()
        onPress = nil
    }
}
