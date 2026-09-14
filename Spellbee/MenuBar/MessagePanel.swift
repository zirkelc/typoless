import AppKit
import SwiftUI

/**
 A short message under the menu bar icon, shown when something needs saying.

 A panel rather than a system notification. Notifications need a permission
 prompt, which is a poor thing to ask of someone installing an app whose whole
 pitch is that it touches as little as possible, and they are meant for things
 you can afford to read later. This says the correction did not land, while the
 user is still looking at the field it did not land in.

 Non-activating, like the correction overlay, because taking focus would move
 the caret out of whatever they are typing in. That also means it cannot be
 clicked, so it says its piece and goes away on its own.
 */
@MainActor
final class MessagePanel {
    /** Long enough to read a sentence, short enough not to sit in the way. */
    private let duration: Duration = .seconds(4)

    private let panel: NSPanel
    private let hosting: NSHostingView<MessageView>
    private var dismissal: Task<Void, Never>?

    init() {
        hosting = NSHostingView(rootView: MessageView(text: ""))

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.contentView = hosting
    }

    /**
     Shows the message under a status item button.

     Anchored to the button rather than to a corner of the screen, so on a Mac
     with several displays it appears under the icon the user just triggered
     from rather than wherever the system decided the primary screen is.
     */
    func show(_ text: String, under button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }

        hosting.rootView = MessageView(text: text)

        let size = hosting.fittingSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))

        /** Centred on the icon, then nudged inside the screen if that would hang off it. */
        var origin = NSPoint(
            x: anchor.midX - size.width / 2,
            y: anchor.minY - size.height - 6
        )

        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            let margin: CGFloat = 8
            origin.x = min(
                max(origin.x, screen.visibleFrame.minX + margin),
                screen.visibleFrame.maxX - size.width - margin
            )
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: self?.duration ?? .seconds(4))

            guard !Task.isCancelled else { return }

            self?.panel.orderOut(nil)
        }
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        panel.orderOut(nil)
    }
}

private struct MessageView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 260, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor))
            }
    }
}
