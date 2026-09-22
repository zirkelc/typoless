@preconcurrency import ApplicationServices
import AppKit
import FoundationModels
import Observation

/**
 Tracks the two gates the app needs before it can do anything useful.

 Neither can be granted programmatically, so the only honest thing the UI can do
 is show live status, deep-link into the right Settings pane, and notice the
 moment the user comes back having flipped the switch.
 */
@MainActor
@Observable
final class PermissionsModel {
    /** Whether this process may read and write text in other applications. */
    private(set) var isAccessibilityTrusted: Bool

    /** Whether the on-device model is usable, and if not, why. */
    private(set) var modelAvailability: SystemLanguageModel.Availability

    /** Called whenever a gate opens or closes, including outside any UI. */
    @ObservationIgnored
    var onChange: (() -> Void)?

    private var pollTask: Task<Void, Never>?

    /**
     Written once during init and read once during deinit, which runs outside
     the main actor. Never mutated after init, so the unchecked access is safe.
     */
    @ObservationIgnored
    private nonisolated(unsafe) var trustObserver: (any NSObjectProtocol)?

    var isReady: Bool {
        isAccessibilityTrusted && modelAvailability == .available
    }

    init() {
        isAccessibilityTrusted = Self.checkTrustOfferingToRegister()
        modelAvailability = SystemLanguageModel.default.availability

        Log.permissions.info(
            "Launched with accessibility trusted: \(self.isAccessibilityTrusted, privacy: .public), model: \(String(describing: self.modelAvailability), privacy: .public)"
        )

        /**
         The system posts this when any application's accessibility trust
         changes, which turns most grants into an instant update rather than
         one that waits for the next poll.
         */
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let trustObserver {
            DistributedNotificationCenter.default().removeObserver(trustObserver)
        }
    }

    /**
     Checks accessibility trust with the prompt option set, which asks the
     system to offer the app to the user if it has never been seen before.

     Whether anything is shown is entirely the system's call. It stays silent
     when the app is already trusted, and it also stays silent for a sandboxed
     app, where the request is dropped without a trace and the app never even
     reaches the list in System Settings. That is why this app is unsandboxed.
     Run it first, before any plain trust check, since the offer is tied to a
     process's first request.
     */
    private static func checkTrustOfferingToRegister() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: kCFBooleanTrue as Any] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func refresh() {
        var didChange = false

        let trusted = AXIsProcessTrusted()
        if trusted != isAccessibilityTrusted {
            isAccessibilityTrusted = trusted
            didChange = true
            Log.permissions.info("Accessibility trust changed to \(trusted, privacy: .public)")
        }

        let availability = SystemLanguageModel.default.availability
        if availability != modelAvailability {
            modelAvailability = availability
            didChange = true
            Log.permissions.info("Model availability changed to \(String(describing: availability), privacy: .public)")
        }

        if didChange {
            onChange?()
        }
    }

    /**
     Polls while a permissions UI is on screen. The distributed notification
     covers accessibility, but model availability has no equivalent signal, and
     a user who enables Apple Intelligence mid-onboarding should still see the
     row turn green without relaunching.
     */
    func startMonitoring() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openAppleIntelligenceSettings() {
        open("x-apple.systempreferences:com.apple.Siri-Settings.extension")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

extension SystemLanguageModel.Availability {
    /** User-facing explanation of why the model cannot be used right now. */
    var explanation: String {
        switch self {
        case .available:
            return "The on-device model is ready."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings."
        case .unavailable(.modelNotReady):
            return "macOS is still downloading the model. This finishes on its own."
        case .unavailable(.deviceNotEligible):
            return "This Mac does not support Apple Intelligence."
        case .unavailable:
            return "The on-device model is unavailable."
        }
    }

    /** Whether the user can do anything about the current state. */
    var isActionable: Bool {
        switch self {
        case .available, .unavailable(.deviceNotEligible), .unavailable(.modelNotReady):
            return false
        default:
            return true
        }
    }
}
