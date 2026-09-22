import AppKit

/**
 The window the correction animation is drawn into.

 It floats above the app being corrected without ever taking focus: a
 non-activating panel that cannot become key or main, ignores every mouse event,
 and follows the user across spaces. Taking focus would move the caret out of
 the text field we are in the middle of editing.
 */
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        /**
         Above normal windows and full-screen apps, but below the menu bar and
         its panels so it never covers system UI. `.screenSaver` is far above
         both, so a field near the top of the screen had its overlay drawn over
         the menu bar, and over this app's own message panel.
         */
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
