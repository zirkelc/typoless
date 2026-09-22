import AppKit
import Carbon.HIToolbox

/**
 One system-wide shortcut, claimed through Carbon.

 `RegisterEventHotKey` is the only way to take a shortcut system-wide without an
 event tap, and it needs no permission of its own. That last part is why it is
 used here for more than the obvious trigger: monitoring key presses passively,
 through `NSEvent`, quietly needs Input Monitoring on top of accessibility, and
 asking for a second permission to notice a keystroke is a poor trade when the
 shortcut can simply be claimed instead.

 Claiming rather than observing also consumes the keystroke, so it never reaches
 the field underneath. For a trigger that is essential; typing the shortcut into
 the very text it is meant to correct would be absurd.
 */
@MainActor
final class CarbonHotKey {
    /** Shared by every shortcut this app registers: "SPBE". */
    private static let signature = OSType(0x5350_4245)

    private let identifier: UInt32

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    fileprivate var onFire: (() -> Void)?

    /**
     - Parameter identifier: Distinguishes this shortcut from the app's others.
       Carbon delivers every registered shortcut to every installed handler, so
       without it one shortcut would fire all of them.
     */
    init(identifier: UInt32) {
        self.identifier = identifier
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, onFire: @escaping () -> Void) -> Bool {
        guard hotKeyRef == nil else { return true }

        self.onFire = onFire

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1,
            &eventType,
            context,
            &handlerRef
        )
        guard installStatus == noErr else {
            Log.app.error("Could not install hot key handler: \(installStatus, privacy: .public)")
            return false
        }

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: identifier),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        /**
         Another app holding the same shortcut is the normal failure here, and
         it is silent from the user's side, so say so.
         */
        guard registerStatus == noErr else {
            Log.app.error("Could not register hot key, it may be taken: \(registerStatus, privacy: .public)")
            unregister()
            return false
        }

        return true
    }

    /**
     Releases the Carbon registrations without going through the main actor.

     The installed handler holds this object as an untyped pointer and
     dereferences it on every matching key press, so an instance released while
     still registered would be read after it was freed. Nothing transient owns
     one today, which is exactly why this is easy to get wrong later.
     */
    isolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        onFire = nil
    }

    fileprivate var registeredIdentifier: UInt32 { identifier }
}

/**
 Carbon hands control back on the main thread, so hopping actors would only add
 a turn of latency to something the user is waiting on.

 Returns `eventNotHandledErr` for anything belonging to another shortcut, so the
 event carries on to the handler that does want it.
 */
private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let context, let event else { return OSStatus(eventNotHandledErr) }

    var pressed = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &pressed
    )
    guard status == noErr else { return OSStatus(eventNotHandledErr) }

    let hotKey = Unmanaged<CarbonHotKey>.fromOpaque(context).takeUnretainedValue()

    return MainActor.assumeIsolated {
        guard pressed.id == hotKey.registeredIdentifier else {
            return OSStatus(eventNotHandledErr)
        }

        hotKey.onFire?()
        return noErr
    }
}
