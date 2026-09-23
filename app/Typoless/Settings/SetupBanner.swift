import SwiftUI

/**
 What the settings window says above every page while the app cannot work.

 Settings is where someone goes when the app is not doing what they expect, and
 until now every page there answered questions the app was in no position to
 act on: without accessibility trust nothing on any of them has any effect at
 all. The setup window says so, and it is closed by then.

 Shown on every page rather than only on General, because the reason to show it
 is that the page underneath it is inert, and that is true of all of them. Shown
 only while something really is missing, so the ordinary case stays clean.

 Two states, not one. Accessibility is a wall: the app does nothing without it.
 Apple's model missing is a caution, and only while Apple's model is the one
 selected, since a downloaded model corrects perfectly well without Apple
 Intelligence ever being turned on.
 */
struct SetupBanner: View {
    let model: AppModel

    var body: some View {
        if let notice {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: notice.isBlocking ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(notice.isBlocking ? Color.orange : Color.secondary)
                    .accessibilityHidden(true)

                Text(notice.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button("Set Up…") { model.showOnboarding() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: SettingsSurface<EmptyView>.width, alignment: .leading)
            .background(notice.isBlocking ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.08))
            .accessibilityElement(children: .combine)

            Divider()
        }
    }

    private struct Notice {
        let message: String
        let isBlocking: Bool
    }

    private var notice: Notice? {
        let permissions = model.permissions

        guard permissions.isAccessibilityTrusted else {
            return Notice(
                message: "Typoless cannot read or write text until Accessibility is allowed. Nothing on this page has any effect until then.",
                isBlocking: true
            )
        }

        /** A downloaded model needs nothing from Apple Intelligence, so it is not asked about. */
        guard model.preferences.backend == .appleOnDevice,
              permissions.modelAvailability != .available
        else { return nil }

        return Notice(
            message: "Apple's on-device model is not ready. \(permissions.modelAvailability.explanation)",
            isBlocking: false
        )
    }
}
