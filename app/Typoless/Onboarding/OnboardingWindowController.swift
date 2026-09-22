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

        /** An accessory app has to ask, or the window opens behind everything. */
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        model.permissions.stopMonitoring()
        window?.orderOut(nil)
    }

    /** The red button does not go through `close`, so it needs its own hook. */
    func windowWillClose(_ notification: Notification) {
        model.permissions.stopMonitoring()
    }

    private func makeWindow() -> NSWindow {
        let view = OnboardingView(model: model) { [weak self] in
            self?.close()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = "Set Up Typoless"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(window.contentView?.fittingSize ?? window.frame.size)

        return window
    }
}
