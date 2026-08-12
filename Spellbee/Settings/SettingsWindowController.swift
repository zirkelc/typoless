import AppKit
import SwiftUI

/**
 Hosts the settings window.

 An AppKit window for the same reason the setup window is one: opening it from
 the menu bar is then a direct call rather than a round trip through an
 environment action that only exists inside a SwiftUI view hierarchy.
 */
@MainActor
final class SettingsWindowController {
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
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Spellbee Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.center()

        return window
    }
}
