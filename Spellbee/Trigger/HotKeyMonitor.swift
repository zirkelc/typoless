import AppKit
import Carbon.HIToolbox

/**
 A conventional global shortcut, registered through Carbon.

 Unlike the modifier double tap this one has to be *consumed*: if the keystroke
 reached the app underneath, the shortcut would type into the very field it is
 meant to correct. `RegisterEventHotKey` is the only way to claim a shortcut
 system-wide without an event tap, and it needs no permission of its own.

 The shortcut is fixed for now. The recorder UI arrives with settings.
 */
@MainActor
final class HotKeyMonitor {
    /**
     Default shortcut: ⌥⌘Space.

     Plain ⌥Space would be the obvious choice but is commonly taken by
     launchers, and losing the registration to another app is silent.
     */
    static let defaultKeyCode = UInt32(kVK_Space)
    static let defaultModifiers = UInt32(optionKey | cmdKey)

    var onFire: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func start(keyCode: UInt32 = defaultKeyCode, modifiers: UInt32 = defaultModifiers) {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            context,
            &handlerRef
        )
        guard installStatus == noErr else {
            Log.app.error("Could not install hot key handler: \(installStatus, privacy: .public)")
            return
        }

        let identifier = EventHotKeyID(signature: OSType(0x5350_4245), id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        /**
         Another app holding the same shortcut is the normal failure here, and
         it is silent from the user's side, so say so.
         */
        if registerStatus != noErr {
            Log.app.error("Could not register hot key, it may be taken: \(registerStatus, privacy: .public)")
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    fileprivate func fire() {
        onFire?()
    }
}

/**
 Carbon hands control back on the main thread, so hopping actors would only add
 a turn of latency to something the user is waiting on.
 */
private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let context else { return OSStatus(eventNotHandledErr) }

    let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.fire()
    }
    return noErr
}
