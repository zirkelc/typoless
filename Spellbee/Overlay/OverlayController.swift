import AppKit
import Observation
import SwiftUI

/**
 Shows and hides the correction overlay.

 Takes rects in the top-left origin space the accessibility APIs report, since
 that is where every caller gets them. Callers never deal with the Cocoa flip.
 */
@MainActor
@Observable
final class OverlayController {
    /** Breathing room so the glow is not clipped by the glyphs it traces. */
    private let padding: CGFloat = 4

    private(set) var isVisible = false

    @ObservationIgnored private var panel: OverlayPanel?

    /**
     Watches for the user moving to another app.

     The overlay is drawn at a fixed place on screen over a specific field. Once
     the user is somewhere else that position means nothing, and because the
     panel floats above everything and joins every space, it would otherwise sit
     there over unrelated windows until the correction finished.
     */
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    /**
     Places the overlay over one or more regions of the screen.

     - Parameter rects: Regions to trace, in top-left origin screen coordinates.
       Usually one per visual line of the text being corrected.
     */
    func show(over rects: [CGRect]) {
        let usable = rects.filter { $0.width > 0 && $0.height > 0 }
        guard let union = usable.unionOfAll else {
            Log.overlay.warning("Refusing to show overlay with no usable rects")
            return
        }

        let frame = union.insetBy(dx: -padding, dy: -padding)

        /**
         Laid out relative to the window's own top-left corner, which is the
         same origin SwiftUI uses, so no flip is needed inside the panel.
         */
        let local = usable.map { rect in
            CGRect(
                x: rect.minX - frame.minX,
                y: rect.minY - frame.minY,
                width: rect.width,
                height: rect.height
            )
        }

        let panel = existingPanel()
        panel.setFrame(ScreenGeometry.cocoaRect(fromTopLeft: frame), display: false)
        panel.contentView = NSHostingView(rootView: OverlayView(rects: local))
        panel.orderFrontRegardless()
        isVisible = true

        watchForAppSwitch()
    }

    func hide() {
        stopWatchingForAppSwitch()

        guard isVisible else { return }
        panel?.orderOut(nil)
        isVisible = false
    }

    private func watchForAppSwitch() {
        guard activationObserver == nil else { return }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.overlay.info("Hiding the overlay because the user switched apps")
                self?.hide()
            }
        }
    }

    private func stopWatchingForAppSwitch() {
        guard let activationObserver else { return }

        NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        self.activationObserver = nil
    }

    private func existingPanel() -> OverlayPanel {
        if let panel { return panel }

        let panel = OverlayPanel()
        self.panel = panel
        return panel
    }
}

private extension Array where Element == CGRect {
    var unionOfAll: CGRect? {
        guard let first else { return nil }
        return dropFirst().reduce(first) { $0.union($1) }
    }
}
