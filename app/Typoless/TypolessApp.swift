import AppKit
import ImageIO
import SwiftUI

@main
struct TypolessApp: App {
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
    /**
     Lazy so that a test run, which launches the app only to host the tests,
     never builds it: the model arms global event monitors and loads a model.
     */
    private lazy var model = AppModel()

    private var statusItem: StatusItemController?
    private var onboarding: OnboardingWindowController?
    private var settings: SettingsWindowController?
    private var historyWindow: HistoryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isHostingTests else { return }

        let onboarding = OnboardingWindowController(model: model)
        self.onboarding = onboarding

        let settings = SettingsWindowController(model: model)
        self.settings = settings

        let historyWindow = HistoryWindowController(
            history: model.history,
            describeModel: { [weak model] in model?.activeModel.displayName ?? "unknown" }
        ) { [weak model] in
            model?.showSettings(.corrections)
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
         Opens setup and starts a correction two seconds later, the way the
         shortcut would, so correcting the practice field can be checked from a
         script. It calls the trigger directly rather than pressing the button,
         so it does not exercise the button's own focus handling.
         */
        if ProcessInfo.processInfo.arguments.contains("--try-onboarding") {
            Task { @MainActor in
                onboarding.show()
                try? await Task.sleep(for: .seconds(2))
                model.trigger()
            }
        }

        /**
         Opens settings and walks every tab a few times, logging how long each
         switch takes to lay out and draw, so the window's speed can be measured
         and profiled rather than judged by feel.
         */
        if ProcessInfo.processInfo.arguments.contains("--cycle-settings") {
            Task { @MainActor in
                settings.show()
                try? await Task.sleep(for: .seconds(1))

                /**
                 The longest the main thread went without running a tick, which
                 is the freeze a person feels. Timing the switch call alone
                 misses work the switch schedules for a moment later, such as
                 the window resizing to fit the page.
                 */
                var lastTick = ContinuousClock.now
                var longestGap = Duration.zero
                let ticker = Timer(timeInterval: 0.004, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        let now = ContinuousClock.now
                        longestGap = max(longestGap, now - lastTick)
                        lastTick = now
                    }
                }
                RunLoop.main.add(ticker, forMode: .common)

                /**
                 Starts on the last tab, so the first measured step really is a
                 switch: settings opens on General, and selecting the tab already
                 shown does nothing.
                 */
                settings.showForMeasuring(SettingsTab.allCases.last!)
                try? await Task.sleep(for: .milliseconds(600))

                for round in 1...3 {
                    for tab in SettingsTab.allCases {
                        lastTick = .now
                        longestGap = .zero
                        settings.showForMeasuring(tab)
                        try? await Task.sleep(for: .milliseconds(600))

                        /**
                         The switch blocks the main thread, so the tick after it
                         always measures at least as long as the call itself.
                         */
                        print("cycle round=\(round) tab=\(tab.rawValue) freeze=\(longestGap.formatted(.units(allowed: [.milliseconds])))")
                    }
                }

                ticker.invalidate()
                NSApp.terminate(nil)
            }
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

    /**
     Whether this launch only hosts the unit tests. Xcode sets the variable in
     the host process before the tests load.
     */
    private static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
