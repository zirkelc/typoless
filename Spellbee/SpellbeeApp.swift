import AppKit
import SwiftUI

@main
struct SpellbeeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        /**
         The app's windows are all managed by AppKit, but an `App` must declare
         at least one scene. Settings is the natural placeholder, and it is
         never presented on its own.
         */
        Settings {
            EmptyView()
        }
    }
}

/**
 Owns everything that outlives a window.

 The model lives here rather than in `@State` on the `App` so there is exactly
 one of it: SwiftUI may evaluate an `App`'s stored property initialisers more
 than once, and a second model would mean a second set of global event monitors
 and a second menu bar item.
 */
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()

    private var statusItem: StatusItemController?
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let onboarding = OnboardingWindowController(model: model)
        self.onboarding = onboarding

        model.onShowOnboarding = { [weak onboarding] in onboarding?.show() }
        statusItem = StatusItemController(model: model)

        if !UserDefaults.standard.bool(forKey: DefaultsKey.hasCompletedOnboarding) {
            onboarding.show()
        }

        #if DEBUG
        /**
         Runs the backend comparison without a menu click, so its results can be
         collected from a script rather than by hand.
         */
        if ProcessInfo.processInfo.arguments.contains("--compare-backends") {
            Task { await model.compareBackends() }
        }
        #endif
    }
}
