import AppKit
import Carbon.HIToolbox

/**
 The conventional global shortcut that triggers a correction.
 */
@MainActor
final class HotKeyMonitor {
    var onFire: (() -> Void)?

    /** What is registered right now, so a change can be noticed and rewired. */
    private(set) var shortcut: Shortcut?

    private let hotKey = CarbonHotKey(identifier: HotKeyIdentifier.correct)

    func start(_ shortcut: Shortcut = .default) {
        guard hotKey.register(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.modifiers,
            onFire: { [weak self] in self?.onFire?() }
        ) else {
            return
        }

        self.shortcut = shortcut
    }

    func stop() {
        hotKey.unregister()
        shortcut = nil
    }
}

/** Keeps the app's shortcuts apart, since Carbon offers every one to every handler. */
enum HotKeyIdentifier {
    static let correct: UInt32 = 1
    static let cancel: UInt32 = 2
}
