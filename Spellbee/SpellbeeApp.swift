import AppKit
import ImageIO
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
    private var settings: SettingsWindowController?
    private var historyWindow: HistoryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let onboarding = OnboardingWindowController(model: model)
        self.onboarding = onboarding

        let settings = SettingsWindowController(model: model)
        self.settings = settings

        let historyWindow = HistoryWindowController(history: model.history) { [weak model] in
            model?.showSettings(.safety)
        }
        self.historyWindow = historyWindow

        model.onShowOnboarding = { [weak onboarding] in onboarding?.show() }
        model.onShowSettings = { [weak settings] tab in settings?.show(tab) }
        model.onShowHistory = { [weak historyWindow] in historyWindow?.show() }
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

        /** Starts the typing spike without a menu click, so a run can be scripted. */
        if ProcessInfo.processInfo.arguments.contains("--observe-typing") {
            model.typingObserver.start()
        }

        /**
         Draws every settings page to a PNG and quits.

         Screenshotting the running window needs a Screen Recording grant, which
         a build script does not have and should not ask for. Rendering the views
         is our own drawing rather than the screen's, so it needs no permission
         and no window, and it is the only way to look at a layout without
         someone sitting in front of it.
         */
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--render-settings") {
            let directory = ProcessInfo.processInfo.arguments[safe: index + 1] ?? NSTemporaryDirectory()
            renderSettingsPages(into: URL(fileURLWithPath: directory))
            NSApp.terminate(nil)
        }
        #endif
    }

    #if DEBUG
    private func renderSettingsPages(into directory: URL) {
        for tab in SettingsTab.allCases {
            let renderer = ImageRenderer(
                content: tab.view(model: model)
                    .frame(width: tab.width)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
            /** Retina, so the text is legible at the size it is drawn. */
            renderer.scale = 2

            guard
                let image = renderer.cgImage,
                let destination = CGImageDestinationCreateWithURL(
                    directory.appending(path: "settings-\(tab.rawValue).png") as CFURL,
                    "public.png" as CFString,
                    1,
                    nil
                )
            else {
                Log.app.error("Could not render \(tab.rawValue, privacy: .public)")
                continue
            }

            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }
    #endif
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
