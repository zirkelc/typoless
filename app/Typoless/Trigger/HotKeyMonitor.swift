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

    /** False when the combination belongs to another app, which is worth saying. */
    @discardableResult
    func start(_ shortcut: Shortcut = .default) -> Bool {
        guard hotKey.register(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.modifiers,
            onFire: { [weak self] in self?.onFire?() }
        ) else {
            return false
        }

        self.shortcut = shortcut

        return true
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
