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

 The one thing that is never blocked is leaving. "Set up later" is on the page
 that can trap somebody, because the two permissions are granted in another
 application and one of them belongs to the Mac rather than to this app: a
 window that can only be left by granting what it asks for is a window that has
 to be force quit on a Mac that cannot grant it.

 One fixed size for every step, so the window does not resize under the pointer
 between one Continue and the next.
 */
struct OnboardingView: View {
    let model: AppModel
    let dragHelp: DragToAllowPanel
    let onDone: () -> Void

    @AppStorage(DefaultsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @State private var page: OnboardingPage = .welcome

    private var permissions: PermissionsModel { model.permissions }

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                /**
                 Scrolls only when a page does not fit, which today none of them
                 does.

                 The window is one size for every step on purpose, so it cannot move
                 under the pointer between one Continue and the next. The risk that
                 carries is silent: a page that grew past the window, by a longer
                 translation or an eighth language, would simply have its lower part
                 cut off with nothing to say so. Scrolling is what turns that from
                 lost content into content one gesture away, and it costs nothing
                 while everything fits, since the bar only appears when it is needed
                 and the buttons below are outside it.
                 */
                ScrollView(.vertical) {
                    VStack(spacing: 18) {
                        if page.isHero {
                            AppIconMark()
                                .padding(.bottom, 6)
                        }

                        header
                        content
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 34)
                    .padding(.top, page.isHero ? 76 : 30)
                    .padding(.bottom, 10)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity)

                footer
            }
        }
        .frame(width: 560, height: 560)
        .preferredColorScheme(.dark)
        /**
         The drag helper belongs to the one page that can need it, and it is a
         window of its own, so nothing else will take it off the screen. It
         decides for itself whether to appear; this only says which page is open.
         */
        .onChange(of: page, initial: true) { _, current in
            if current == .permissions {
                dragHelp.start()
            } else {
                dragHelp.stop()
            }
        }
        /**
         Starting and stopping the poller belongs to the window controller, which
         is told when it closes; this view is not. Re-arming the triggers is
         already wired through `PermissionsModel.onChange`, so doing it here as
         well only made it look as though it happened solely while setup was open.
         */
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(page.title)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)

            Text(page.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .welcome: EmptyView()
        case .triggers: TriggersPage(preferences: model.preferences)
        case .permissions: PermissionsPage(permissions: permissions)
        case .languages: LanguagesPage(preferences: model.preferences)
        case .tryIt: TryItPage(model: model)
        case .history: HistoryPage(preferences: model.preferences, history: model.history)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button(action: advance) {
                Text(page.advanceTitle)
                    .frame(width: 150)
            }
            .buttonStyle(.borderedProminent)
            /**
             Grey while it is blocked, rather than a dimmed version of the
             colour. A tinted button that is only a little paler reads as the
             one to press, which is the opposite of what it is.
             */
            .tint(blocked == nil ? Color.accentColor : Color.white.opacity(0.13))
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(blocked != nil)
            .shadow(color: Color.accentColor.opacity(blocked == nil ? 0.22 : 0), radius: 9)

            notes

            ZStack {
                OnboardingDots(current: page)

                HStack {
                    if let previous = page.previous {
                        Button("Back") { page = previous }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
            }
            .font(.subheadline)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    /** Why the button is grey, and the way past it where there is one. */
    @ViewBuilder private var notes: some View {
        VStack(spacing: 6) {
            if let blocked {
                Text(blocked)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if page == .permissions, !permissions.isReady {
                Button("Set up later") { advance() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .underline()
            }
        }
        .font(.subheadline)
        .frame(height: 34)
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
            return "Typoless stays inactive until you allow both."

        case .languages:
            guard !model.preferences.enabledLanguages.isEmpty else {
                return "Add at least one language."
            }
            return nil

        case .triggers:
            guard model.preferences.triggerDescription == nil else { return nil }
            return "Keep at least one way to start a correction."

        case .welcome, .tryIt, .history:
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
