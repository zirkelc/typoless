import AppKit
import SwiftUI

/**
 Hosts the setup window.

 An AppKit window rather than a SwiftUI `Window` scene, so that opening it from
 the menu bar is a direct call rather than a round trip through an environment
 action that only exists inside a SwiftUI view hierarchy.
 */
@MainActor
final class OnboardingWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }

        /** An accessory app has to ask, or the window opens behind everything. */
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
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
        window.title = "Set Up Spellbee"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(window.contentView?.fittingSize ?? window.frame.size)

        return window
    }
}
