import AppKit
import SwiftUI

/**
 Hosts the correction history.

 Its own window rather than a settings tab, because it is not a setting: it is
 something to reach for when a correction has gone wrong, which is a moment when
 hunting through preferences is the last thing anyone wants to do.
 */
@MainActor
final class HistoryWindowController {
    private let history: CorrectionHistory
    private let onOpenSettings: () -> Void
    private let describeModel: () -> String
    private var window: NSWindow?

    init(
        history: CorrectionHistory,
        describeModel: @escaping () -> String,
        onOpenSettings: @escaping () -> Void
    ) {
        self.history = history
        self.describeModel = describeModel
        self.onOpenSettings = onOpenSettings
    }

    func show() {
        /**
         Here rather than in the view, which is only told it appeared the first
         time: the window is kept rather than released, so reopening it does not
         re-run any SwiftUI lifecycle. Entries were therefore aged out only once
         per launch, and text the app had promised to drop stayed on screen.
         */
        history.prune()

        if window == nil {
            window = makeWindow()
        }

        /** An accessory app has to ask, or the window opens behind everything. */
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Correction History"
        window.contentView = NSHostingView(
            rootView: HistoryView(
                history: history,
                onOpenSettings: onOpenSettings,
                describeModel: describeModel
            )
        )
        window.center()

        return window
    }
}
