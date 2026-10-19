import AppKit
import SwiftUI

/**
 Hosts the setup window.

 An AppKit window rather than a SwiftUI `Window` scene, so that opening it from
 the menu bar is a direct call rather than a round trip through an environment
 action that only exists inside a SwiftUI view hierarchy.
 */
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private var dragHelp: DragToAllowPanel?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }

        /**
         Started here rather than by the view.

         The window is kept rather than released and is only ordered out, so
         SwiftUI is never told the view disappeared and the poller was never
         stopped: an accessibility check and a model availability query, once a
         second, for the rest of the app's life, after a window the user opened
         once on first launch. The window knows when it closes; the view does not.
         */
        model.permissions.startMonitoring()

        /**
         An accessory app has to ask to come forward, and `orderFrontRegardless`
         as well, because an app that is not the active one is not allowed to
         raise a window by asking politely: the menu item can be used from
         another app, and this window is the answer to it.
         */
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        stopHelpers()
        window?.orderOut(nil)
    }

    /** The red button does not go through `close`, so it needs its own hook. */
    func windowWillClose(_ notification: Notification) {
        stopHelpers()
    }

    /**
     Both of the things that watch the world rather than this window.

     The drag helper is a window of its own on top of every other application,
     so a setup window that closed without taking it down would leave it there
     with nothing to close it.
     */
    private func stopHelpers() {
        model.permissions.stopMonitoring()
        dragHelp?.stop()
    }

    private func makeWindow() -> NSWindow {
        let dragHelp = DragToAllowPanel(permissions: model.permissions) { [weak self] in
            self?.show()
        }
        self.dragHelp = dragHelp

        let view = OnboardingView(model: model, dragHelp: dragHelp) { [weak self] in
            self?.close()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = "Set Up Typoless"
        window.titlebarAppearsTransparent = true
        /**
         The title would be printed over the first page, where the window says
         what it is in letters ten times the size.
         */
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        /**
         Setup has one look, and it is this one. The rest of the app follows the
         system appearance, because the rest of the app has to sit in the menu
         bar beside everything else; this window is read once and is allowed to
         be itself.
         */
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.075, green: 0.071, blue: 0.075, alpha: 1)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(window.contentView?.fittingSize ?? window.frame.size)

        return window
    }
}
