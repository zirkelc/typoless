import Carbon.HIToolbox
import Observation
import ServiceManagement
import SwiftUI

/** Keys for values persisted in user defaults. */
enum DefaultsKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let correctorBackend = "correctorBackend"
    static let localModel = "localModel"
    static let guardrailEnabled = "guardrailEnabled"
    static let doubleTapEnabled = "doubleTapEnabled"
    static let doubleTapModifier = "doubleTapModifier"
    static let hotKeyEnabled = "hotKeyEnabled"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let enabledLanguages = "enabledLanguages"
    static let allowedEditKinds = "allowedEditKinds"
    static let sentenceFinalPunctuation = "sentenceFinalPunctuation"
    static let deniedBundleIDs = "deniedBundleIDs"
    static let appOverrides = "appOverrides"
}

/**
 Everything the user can change, and the only thing that reads or writes it.

 Settings used to be read straight out of `UserDefaults` wherever they were
 needed, which is fine for two of them and unworkable for twenty: nothing can
 observe a change, and the default for a missing value ends up written out in
 several places and eventually disagrees with itself. Every property here writes
 through on set, so a view binding and the running engine cannot drift apart.
 */
@MainActor
@Observable
final class Preferences {
    /**
     Called when a change means the triggers have to be rewired.

     Two hooks rather than one, because rebuilding the corrector evicts several
     gigabytes of weights and loads them again. A single "something changed"
     callback made turning off a checkbox cost that, which is a long pause for
     no reason.
     */
    @ObservationIgnored var onTriggersChanged: (() -> Void)?

    /** Called when a change means the corrector has to be rebuilt. */
    @ObservationIgnored var onCorrectorChanged: (() -> Void)?

    // MARK: Triggers

    var isDoubleTapEnabled: Bool {
        didSet {
            write(isDoubleTapEnabled, DefaultsKey.doubleTapEnabled)
            onTriggersChanged?()
        }
    }

    /** Which key is tapped twice. */
    var doubleTapModifier: TapModifier {
        didSet {
            write(doubleTapModifier.rawValue, DefaultsKey.doubleTapModifier)
            onTriggersChanged?()
        }
    }

    var isHotKeyEnabled: Bool {
        didSet {
            write(isHotKeyEnabled, DefaultsKey.hotKeyEnabled)
            onTriggersChanged?()
        }
    }

    var hotKey: Shortcut {
        didSet {
            defaults.set(Int(hotKey.keyCode), forKey: DefaultsKey.hotKeyCode)
            defaults.set(Int(hotKey.modifiers), forKey: DefaultsKey.hotKeyModifiers)
            onTriggersChanged?()
        }
    }

    /**
     Whether the app starts itself when the user logs in.

     Unlike everything else here this is not ours to remember: the system owns
     it, and the user can turn it off in System Settings without telling us. So
     it is read back from `SMAppService` rather than from a stored copy that
     would slowly become a lie.
     */
    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                try newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            } catch {
                Log.app.error("Could not change launch at login: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: Languages

    var enabledLanguages: Set<CorrectionLanguage> {
        didSet {
            /** No languages at all would mean correcting nothing, forever. */
            if enabledLanguages.isEmpty { enabledLanguages = oldValue }
            write(enabledLanguages.map(\.rawValue), DefaultsKey.enabledLanguages)
            onCorrectorChanged?()
        }
    }

    // MARK: Corrections

    /**
     Whether the model's changes are judged before being applied.

     On by default, and the thing that makes this a correction tool rather than
     a rewriting one. Off, whatever the model returns goes straight into the
     field, which is useful for judging a model and risky for everything else.
     */
    var isGuardrailEnabled: Bool {
        didSet {
            write(isGuardrailEnabled, DefaultsKey.guardrailEnabled)
            onCorrectorChanged?()
        }
    }

    var allowedKinds: Set<EditKind> {
        didSet { write(allowedKinds.map(\.rawValue), DefaultsKey.allowedEditKinds) }
    }

    /** Whether a message with no closing mark is given one. See `appOverrides`. */
    var addsSentenceFinalPunctuation: Bool {
        didSet { write(addsSentenceFinalPunctuation, DefaultsKey.sentenceFinalPunctuation) }
    }

    // MARK: Backend

    /**
     Set through `AppModel.use(_:model:)` rather than directly, so that changing
     both at once rebuilds the corrector once instead of twice.
     */
    var backend: CorrectorBackend {
        didSet { write(backend.rawValue, DefaultsKey.correctorBackend) }
    }

    var localModel: LocalModel {
        didSet { write(localModel.rawValue, DefaultsKey.localModel) }
    }

    // MARK: Apps

    /** Apps Spellbee will not touch, by bundle identifier. */
    var deniedBundleIDs: Set<String> {
        didSet { write(Array(deniedBundleIDs), DefaultsKey.deniedBundleIDs) }
    }

    /**
     Per-app answers that differ from the global one.

     A full stop is right in an email and changes the tone of a chat line, so
     the same setting has to be able to say different things in different apps.
     Absent means "whatever the global setting says", which is why the value is
     optional rather than a copy of the default.
     */
    var appOverrides: [String: AppOverride] {
        didSet {
            let encoded = appOverrides.compactMapValues { $0.sentenceFinalPunctuation }
            write(encoded, DefaultsKey.appOverrides)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        isDoubleTapEnabled = defaults.object(forKey: DefaultsKey.doubleTapEnabled) as? Bool ?? true
        doubleTapModifier = defaults.string(forKey: DefaultsKey.doubleTapModifier)
            .flatMap(TapModifier.init) ?? .command
        isHotKeyEnabled = defaults.object(forKey: DefaultsKey.hotKeyEnabled) as? Bool ?? true

        let storedCode = defaults.object(forKey: DefaultsKey.hotKeyCode) as? Int
        let storedModifiers = defaults.object(forKey: DefaultsKey.hotKeyModifiers) as? Int
        hotKey = Shortcut(
            keyCode: UInt32(storedCode ?? Int(Shortcut.default.keyCode)),
            modifiers: UInt32(storedModifiers ?? Int(Shortcut.default.modifiers))
        )

        let languages = (defaults.array(forKey: DefaultsKey.enabledLanguages) as? [String])?
            .compactMap(CorrectionLanguage.init)
        enabledLanguages = Set(languages ?? CorrectionLanguage.allCases)

        /** Absent means never set, which should mean on rather than off. */
        isGuardrailEnabled = defaults.object(forKey: DefaultsKey.guardrailEnabled) as? Bool ?? true

        let kinds = (defaults.array(forKey: DefaultsKey.allowedEditKinds) as? [String])?
            .compactMap(EditKind.init)
        allowedKinds = Set(kinds ?? EditKind.allCases)

        addsSentenceFinalPunctuation = defaults
            .object(forKey: DefaultsKey.sentenceFinalPunctuation) as? Bool ?? true

        backend = defaults.string(forKey: DefaultsKey.correctorBackend)
            .flatMap(CorrectorBackend.init) ?? .appleOnDevice

        /**
         Gemma by default because it is the one that measures well: it leads fix
         recall by roughly 15 points over Apple's on-device model in both
         languages. Anyone who had a since-removed model selected lands here
         too, since an unknown name reads back as nil.
         */
        localModel = defaults.string(forKey: DefaultsKey.localModel)
            .flatMap(LocalModel.init) ?? .gemma4_e4b

        let denied = defaults.array(forKey: DefaultsKey.deniedBundleIDs) as? [String]
        deniedBundleIDs = Set(denied ?? Array(TextTargetResolver.defaultDeniedBundleIDs))

        let overrides = defaults.dictionary(forKey: DefaultsKey.appOverrides) as? [String: Bool] ?? [:]
        appOverrides = overrides.mapValues { AppOverride(sentenceFinalPunctuation: $0) }
    }

    /** What applies in a given app, once its own answers are taken into account. */
    func settings(for bundleID: String?) -> AppSettings {
        let override = bundleID.flatMap { appOverrides[$0] }

        return AppSettings(
            allowedKinds: allowedKinds,
            addsSentenceFinalPunctuation: override?.sentenceFinalPunctuation
                ?? addsSentenceFinalPunctuation
        )
    }

    /**
     Persists a value, and nothing else.

     Most settings need no side effect at all: the kinds to allow, full stops,
     the deny-list and the per-app answers are read afresh at the start of every
     correction, so changing one takes effect on the next keystroke without
     anything being rebuilt.
     */
    private func write(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}

/** One app's departures from the global settings. Nil means it does not depart. */
struct AppOverride: Equatable, Sendable {
    var sentenceFinalPunctuation: Bool?
}

/** A key and its modifiers, in the Carbon values `RegisterEventHotKey` wants. */
struct Shortcut: Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    /**
     ⌃⌥⌘Space.

     Space with fewer modifiers is crowded: plain ⌥Space is commonly taken by
     launchers, ⌃⌘Space is the emoji picker, and ⌥⌘Space is the system's Finder
     search window. That last one was the original default and it never worked:
     registration succeeded, the correction started, and Finder came forward
     anyway, so the guard against the frontmost app changing threw every result
     away. A shortcut can be claimed and still lose.
     */
    static let `default` = Shortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey | cmdKey)
    )
}
