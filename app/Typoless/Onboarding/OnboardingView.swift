import AppKit
import SwiftUI

/**
 First-run setup, one step at a time.

 Rows poll their own status, so granting a permission in System Settings turns a
 row green without the user coming back and clicking anything.

 Each step is blocked until it is satisfied, which is the point of the shape: the
 sample field at the end cannot be reached until there is a permission, a
 language and a trigger behind it, so it can only ever demonstrate the app
 working. The single window this replaces let anyone reach the field first, press
 the button, and watch nothing happen.

 One fixed size for every step, so the window does not resize under the pointer
 between one Continue and the next.
 */
struct OnboardingView: View {
    let model: AppModel
    let onDone: () -> Void

    @AppStorage(DefaultsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @State private var page: OnboardingPage = .welcome

    private var permissions: PermissionsModel { model.permissions }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progressBar

            VStack(alignment: .leading, spacing: 20) {
                header
                content
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            footer
        }
        .frame(width: 520, height: 520)
        /**
         Starting and stopping the poller belongs to the window controller, which
         is told when it closes; this view is not. Re-arming the triggers is
         already wired through `PermissionsModel.onChange`, so doing it here as
         well only made it look as though it happened solely while setup was open.
         */
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)

                Capsule()
                    .fill(.tint)
                    .frame(width: proxy.size.width * page.progress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .animation(.easeInOut(duration: 0.2), value: page)
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(page.title)
                .font(.title.bold())

            Text(page.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .welcome: WelcomePage()
        case .permissions: PermissionsPage(permissions: permissions)
        case .languages: LanguagesPage(preferences: model.preferences)
        case .triggers: TriggersPage(preferences: model.preferences)
        case .tryIt: TryItPage(model: model)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let previous = page.previous {
                Button("Back") { page = previous }
            }

            if let blocked {
                Text(blocked)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(page.advanceTitle) { advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(blocked != nil)
        }
        .padding(20)
    }

    /**
     Why the button is disabled, or nil when it is not.

     The reason is shown rather than only the disabled button, since a button
     that does nothing and says nothing is the commonest way a setup window
     traps someone.
     */
    private var blocked: String? {
        switch page {
        case .permissions:
            guard !permissions.isReady else { return nil }
            return "Typoless stays inactive until both are allowed."

        case .languages:
            guard model.preferences.enabledLanguages.isEmpty else { return nil }
            return "Add at least one language."

        case .triggers:
            guard model.preferences.triggerDescription == nil else { return nil }
            return "Keep at least one way to start a correction."

        case .welcome, .tryIt:
            return nil
        }
    }

    private func advance() {
        guard let next = page.next else {
            hasCompletedOnboarding = true
            onDone()
            return
        }

        page = next
    }
}
