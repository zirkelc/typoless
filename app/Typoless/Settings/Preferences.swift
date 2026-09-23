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
    static let cancelKeyCode = "cancelKeyCode"
    static let cancelKeyModifiers = "cancelKeyModifiers"
    static let languageSettings = "languageSettings"
    static let deniedBundleIDs = "deniedBundleIDs"
    static let allowedBundleIDs = "allowedBundleIDs"
    static let historyRetention = "historyRetention"
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

    /** Called when how much history to keep has changed. */
    @ObservationIgnored var onHistoryRetentionChanged: (() -> Void)?

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
     The key that abandons a correction in progress.

     Claimed only while a pass is running, which is what lets it be a bare key
     with no modifiers: the rest of the time it belongs to whatever the user is
     typing in.
     */
    var cancelKey: Shortcut {
        didSet {
            defaults.set(Int(cancelKey.keyCode), forKey: DefaultsKey.cancelKeyCode)
            defaults.set(Int(cancelKey.modifiers), forKey: DefaultsKey.cancelKeyModifiers)
        }
    }

    /**
     Whether the app starts itself when the user logs in.

     Unlike everything else here this is not ours to remember: the system owns
     it, and the user can turn it off in System Settings without telling us. So
     it is read back from `SMAppService` after every change, and again whenever
     settings are shown, rather than kept as a stored copy that would slowly
     become a lie.

     Stored all the same, because a computed property is invisible to
     observation. It used to be one, and the switch wrote to the system and then
     drew the old state, since nothing a view was watching had changed.
     */
    private(set) var launchAtLogin: LaunchAtLogin = .current

    /** Asks the system, then shows whatever it actually decided. */
    func setLaunchesAtLogin(_ isOn: Bool) {
        do {
            try isOn ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        } catch {
            Log.app.error("Could not change launch at login: \(String(describing: error), privacy: .public)")
        }

        refreshLaunchAtLogin()
    }

    /** Picks up a change made in System Settings while we were not looking. */
    func refreshLaunchAtLogin() {
        let current = LaunchAtLogin.current
        if launchAtLogin != current { launchAtLogin = current }
    }

    // MARK: Languages

    /**
     Everything each language is allowed to do, and which model does it.

     Keyed by language rather than held as one global set, because the rules are
     not the same everywhere: an umlaut is a German question and an apostrophe
     is mostly an English one, and someone who wants their German nouns
     capitalised may well not want that anywhere else.
     */
    var languageSettings: [CorrectionLanguage: LanguageSettings] {
        didSet {
            /** No languages at all would mean correcting nothing, forever. */
            if !languageSettings.values.contains(where: \.isEnabled) {
                languageSettings = oldValue
            }

            writeLanguageSettings()

            /**
             Only when the corrector would actually be built differently.

             Which rules a language allows, and which model it prefers, are read
             afresh at the start of every correction, so changing one takes
             effect on the next keystroke with nothing to rebuild. Only the set
             of enabled languages is baked in, by the detector. Firing on every
             change meant that ticking a single correction checkbox evicted
             several gigabytes of weights and loaded them again, five times over
             if you ticked five boxes, with the old copy unloading while the new
             one loaded.
             */
            if Self.enabledLanguages(in: oldValue) != Self.enabledLanguages(in: languageSettings) {
                onCorrectorChanged?()
            }
        }
    }

    private static func enabledLanguages(in settings: [CorrectionLanguage: LanguageSettings]) -> Set<CorrectionLanguage> {
        Set(settings.filter(\.value.isEnabled).keys)
    }

    var enabledLanguages: [CorrectionLanguage] {
        CorrectionLanguage.allCases.filter { languageSettings[$0]?.isEnabled ?? false }
    }

    /**
     How to start a correction, phrased as the user would do it, or nil when
     both triggers are off.

     Each trigger carries its own verb, since the two are not done the same way:
     one is tapped twice and the other is pressed once, and "press ⌘ twice or
     ⌃⌥⌘Space" made the second read as another double tap. Nil rather than an
     empty string, because a hint that says to press nothing is worse than no
     hint at all.
     */
    var triggerDescription: String? {
        var phrases: [String] = []

        if isDoubleTapEnabled {
            phrases.append("double tap \(doubleTapModifier.symbol)")
        }
        if isHotKeyEnabled {
            phrases.append("press \(hotKey.displayName)")
        }

        guard let first = phrases.first else { return nil }

        return ([first.prefix(1).uppercased() + first.dropFirst()] + phrases.dropFirst())
            .joined(separator: " or ")
    }

    // MARK: Corrections

    /**
     Whether the model's changes are judged before being applied.

     Always on in a shipped build, and there is no switch for it.

     There was one, and the measurements took it away. Off buys 1 English fix
     and 7 German ones across the datasets and costs 15 and 22 changes nobody
     asked for, and the two worst answers the app has ever applied, a reply
     returned entirely in capitals and Apple's schema text written into the
     message, both reached the field with it off.

     It survives as a flag because judging a model means seeing what the model
     did rather than what survived, which is what the debug menu offers and what
     `Eval` reports in both columns.
     */
    var isGuardrailEnabled: Bool {
        didSet {
            write(isGuardrailEnabled, DefaultsKey.guardrailEnabled)
            onCorrectorChanged?()
        }
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

    /** Apps Typoless will not touch, by bundle identifier. Always applies. */
    var deniedBundleIDs: Set<String> {
        didSet { write(Array(deniedBundleIDs), DefaultsKey.deniedBundleIDs) }
    }

    /** If any are named, the only apps Typoless will touch. Empty means everywhere. */
    var allowedBundleIDs: Set<String> {
        didSet { write(Array(allowedBundleIDs), DefaultsKey.allowedBundleIDs) }
    }

    var appPolicy: AppPolicy {
        AppPolicy(denied: deniedBundleIDs, allowed: allowedBundleIDs)
    }

    // MARK: History

    /** How long a correction stays recoverable, or whether it is kept at all. */
    var historyRetention: HistoryRetention {
        didSet {
            write(historyRetention.rawValue, DefaultsKey.historyRetention)
            onHistoryRetentionChanged?()
        }
    }

    /** Nil for a missing value and for one that cannot be a key code at all. */
    private static func storedCode(_ defaults: UserDefaults, _ key: String) -> UInt32? {
        (defaults.object(forKey: key) as? Int).flatMap(UInt32.init(exactly:))
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        isDoubleTapEnabled = defaults.object(forKey: DefaultsKey.doubleTapEnabled) as? Bool ?? true
        doubleTapModifier = defaults.string(forKey: DefaultsKey.doubleTapModifier)
            .flatMap(TapModifier.init) ?? .command
        isHotKeyEnabled = defaults.object(forKey: DefaultsKey.hotKeyEnabled) as? Bool ?? true

        /**
         `exactly:` rather than `UInt32(_:)`, which traps on a negative or
         oversized value. This runs before the app finishes launching, so a
         defaults file damaged by an unclean shutdown, or a mistyped `defaults
         write`, would abort every launch with no way to reach settings and undo
         it. Every other value here already falls back rather than crashing.
         */
        hotKey = Shortcut(
            keyCode: Self.storedCode(defaults, DefaultsKey.hotKeyCode) ?? Shortcut.default.keyCode,
            modifiers: Self.storedCode(defaults, DefaultsKey.hotKeyModifiers) ?? Shortcut.default.modifiers
        )

        cancelKey = Shortcut(
            keyCode: Self.storedCode(defaults, DefaultsKey.cancelKeyCode) ?? Shortcut.cancel.keyCode,
            modifiers: Self.storedCode(defaults, DefaultsKey.cancelKeyModifiers) ?? Shortcut.cancel.modifiers
        )

        languageSettings = Self.readLanguageSettings(from: defaults)

        #if DEBUG
        /** Absent means never set, which should mean on rather than off. */
        isGuardrailEnabled = defaults.object(forKey: DefaultsKey.guardrailEnabled) as? Bool ?? true
        #else
        /** A value stored by a build that still had the switch is ignored. */
        isGuardrailEnabled = true
        #endif

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
        deniedBundleIDs = Set(denied ?? Array(AppPolicy.defaultDenied))

        /** Empty means everywhere, which is the right thing to start with. */
        allowedBundleIDs = Set(defaults.array(forKey: DefaultsKey.allowedBundleIDs) as? [String] ?? [])

        historyRetention = defaults.string(forKey: DefaultsKey.historyRetention)
            .flatMap(HistoryRetention.init) ?? .threeHours

    }

    /** What applies in a given app, once its own answers are taken into account. */
    func settings(for bundleID: String?) -> AppSettings {
        return AppSettings(languages: languageSettings)
    }

    /**
     Stored as one dictionary per language rather than as separate keys, so a
     language added later needs no migration: an absent entry simply falls back
     to that language's own defaults.
     */
    private func writeLanguageSettings() {
        let encoded = languageSettings.reduce(into: [String: [String: Any]]()) { result, entry in
            var value: [String: Any] = [
                "enabled": entry.value.isEnabled,
                "rules": entry.value.allowedRules.map(\.rawValue),
                /**
                 Every rule the user has been shown, on or off, so a rule added
                 in a later version can start on rather than read as one they
                 turned off.
                 */
                "known": entry.key.applicableRules.map(\.rawValue),
            ]

            /**
             Added only when there is one. An absent model has to be absent from
             the dictionary rather than present and nil: user defaults stores
             property lists, a boxed `Optional.none` is not one, and the whole
             write is refused when it contains one. That is silent, so every
             change to these settings was being discarded.
             */
            if let model = entry.value.model {
                value["model"] = model.storageKey
            }

            result[entry.key.rawValue] = value
        }

        write(encoded, DefaultsKey.languageSettings)
    }

    private static func readLanguageSettings(from defaults: UserDefaults) -> [CorrectionLanguage: LanguageSettings] {
        let stored = defaults.dictionary(forKey: DefaultsKey.languageSettings) as? [String: [String: Any]] ?? [:]

        return Dictionary(uniqueKeysWithValues: CorrectionLanguage.allCases.map { language in
            guard let entry = stored[language.rawValue] else {
                return (language, LanguageSettings.default(for: language))
            }

            let rules = (entry["rules"] as? [String])?.compactMap(CorrectionRule.init)

            /**
             Rules the stored answer predates. A version that did not record
             what it had shown knew every rule but grammar, which came later.
             */
            let known = (entry["known"] as? [String]).map { Set($0.compactMap(CorrectionRule.init)) }
                ?? language.applicableRules.subtracting([.grammar])
            let unseen = language.applicableRules.subtracting(known)

            return (language, LanguageSettings(
                isEnabled: entry["enabled"] as? Bool ?? language.isEnabledByDefault,
                /**
                 A stored choice naming a model the app no longer has reads as
                 nil, which is the default, rather than keeping a language
                 pointed at something that cannot answer.
                 */
                model: (entry["model"] as? String).flatMap(ModelChoice.init(storageKey:)),
                /** Only rules the language has, so a stored set cannot resurrect one. */
                allowedRules: Set(rules ?? Array(language.applicableRules))
                    .union(unseen)
                    .intersection(language.applicableRules)
            ))
        })
    }

    /**
     Persists a value, and nothing else.

     Most settings need no side effect at all: the kinds to allow, full stops,
     the deny-list and the per-app answers are read afresh at the start of every
     correction, so changing one takes effect on the next keystroke without
     anything being rebuilt.
     */
    private func write(_ value: Any, _ key: String) {
        /**
         A value that is not a property list does not fail quietly: `set` raises
         and the process dies. An optional boxed inside a dictionary is the easy
         way to produce one, which has happened here before, so the assertion
         names the setting rather than leaving a stack trace inside Foundation.
         */
        assert(
            PropertyListSerialization.propertyList([key: value], isValidFor: .binary),
            "Not a property list: \(key)"
        )

        defaults.set(value, forKey: key)
    }
}

/**
 What the system says about starting at login.

 More states than a flag, because registering can succeed and still not take
 effect, or fail outright, and a switch that reads "off" after being turned on
 needs to say why. The system may hold the item until the user allows it under
 Login Items, or not be able to find the app to register at all.
 */
enum LaunchAtLogin: Equatable {
    case off
    case on
    case needsApproval
    /** The system cannot find the app to register, usually because it runs from outside Applications. */
    case unavailable

    static var current: LaunchAtLogin {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notFound: return .unavailable
        default: return .off
        }
    }

    /** What the settings line says under the switch, if anything. */
    var note: String? {
        switch self {
        case .needsApproval: return "Waiting for your approval under Login Items in System Settings."
        case .unavailable: return "macOS could not find Typoless to register it. Move Typoless to the Applications folder and try again."
        case .on, .off: return nil
        }
    }
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

    /** Escape on its own, which is only claimed while a correction is running. */
    static let cancel = Shortcut(keyCode: UInt32(kVK_Escape), modifiers: 0)
}
