import AppKit
import SwiftUI

/**
 The instructions for granting accessibility, shown on the window they are for.

 Accessibility is the one permission that cannot be granted by answering a
 dialog. The system offers its own dialog once per app, and after that the only
 route is the Privacy pane, where the user has to find this app in a list of
 everything on the Mac, or add it with a button that opens a file browser at the
 wrong folder. The usual result is somebody switching on the wrong row, or the
 right row for another copy of the app, and coming back to an app that still
 does nothing.

 So the app follows them. While System Settings is in front and the permission
 is still missing, a small window sits along the bottom of it holding the one
 thing that always works: this app, as something to drag into the list. There is
 no guessing which row is which, because the row ends up where it was dropped.

 It appears only when all three are true at once: this permission is missing,
 System Settings is the application in front, and its window can be found. Any
 one of them failing takes the window off the screen, so it cannot be left
 behind over somebody's work.
 */
@MainActor
final class DragToAllowPanel {
    private let permissions: PermissionsModel

    /** Brings setup back to the front, for a user who has lost it behind Settings. */
    private let onReturn: () -> Void

    private var panel: NSPanel?
    private var pollTask: Task<Void, Never>?

    private static let size = CGSize(width: 470, height: 104)

    /** Often enough that the window does not visibly lag when Settings is dragged. */
    private static let interval = Duration.milliseconds(250)

    init(permissions: PermissionsModel, onReturn: @escaping () -> Void) {
        self.permissions = permissions
        self.onReturn = onReturn
    }

    func start() {
        guard pollTask == nil else { return }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.update()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        hide()
    }

    private func update() {
        guard isWanted, let settings = settingsFrame() else {
            hide()
            return
        }

        let frame = SystemSettingsWindow.helperFrame(against: settings, size: Self.size)
        show(at: frame)
    }

    /** Whether there is anything left to explain. */
    private var isWanted: Bool {
        guard !permissions.isAccessibilityTrusted else { return false }

        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        return frontmost == "com.apple.systempreferences"
    }

    private func settingsFrame() -> CGRect? {
        guard let frame = SystemSettingsWindow.currentFrame() else { return nil }

        return SystemSettingsWindow.appKitFrame(
            from: frame,
            mainScreenTop: SystemSettingsWindow.mainScreenTop
        )
    }

    private func show(at frame: CGRect) {
        let panel = panel ?? makePanel()
        self.panel = panel

        panel.setFrame(frame, display: true)

        /**
         Ordered in without being made key, and without activating this app.
         Taking focus here would put System Settings behind the app that is
         telling the user to use System Settings.
         */
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.appearance = NSAppearance(named: .darkAqua)

        let view = DragToAllowView(onReturn: onReturn)
        panel.contentView = NSHostingView(rootView: view)

        return panel
    }
}

/** What the panel says, and the thing it says to drag. */
private struct DragToAllowView: View {
    let onReturn: () -> Void

    private var appName: String {
        let info = Bundle.main.infoDictionary

        return info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? "Typoless"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onReturn) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back to Typoless")

            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Drag \(appName) into the list above, and switch it on.",
                    systemImage: "arrow.up"
                )
                .font(.system(size: 12, weight: .medium))

                dragCard
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.11, green: 0.105, blue: 0.11), in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12)))
    }

    private var dragCard: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)

            Text(appName)
                .font(.system(size: 12))

            Spacer(minLength: 0)

            Text("Drag me")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .overlay(AppBundleDragSource())
        .accessibilityLabel("\(appName), ready to drag into the accessibility list")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }
}

/**
 This app's own bundle, as something another application accepts as a drop.

 The Privacy panes take an application dropped onto their list and add it, which
 is the same act as the plus button and the file browser behind it, with the
 part that goes wrong taken out. The pasteboard carries the bundle this code is
 running from, so the row that appears is this copy of the app and not another
 one with the same name somewhere else on the disk.

 Written in AppKit because the window it lives in never becomes active, and the
 drag has to start from the event that arrives in a window that is not key.
 */
private struct AppBundleDragSource: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }

    func updateNSView(_ view: NSView, context: Context) {}

    final class DragView: NSView, NSDraggingSource {
        /** The size the dragged icon is drawn at, which is the Finder's own. */
        private static let iconSize: CGFloat = 48

        override func mouseDown(with event: NSEvent) {
            let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
            let origin = convert(event.locationInWindow, from: nil)

            item.setDraggingFrame(
                NSRect(
                    x: origin.x - Self.iconSize / 2,
                    y: origin.y - Self.iconSize / 2,
                    width: Self.iconSize,
                    height: Self.iconSize
                ),
                contents: icon
            )

            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        /** The pointer says what this is for before anything is pressed. */
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
