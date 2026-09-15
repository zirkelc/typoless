import Foundation

/** What one language is allowed to do, and which model does it. */
struct LanguageSettings: Equatable, Sendable {
    var isEnabled: Bool

    /**
     Nil means whichever model is the default, which is the usual case.

     Any model, not only a downloaded one. A language naming Apple's model while
     the default is a downloaded one is a real configuration: the two are better
     at different languages, and the point of setting a model per language is to
     say so.
     */
    var model: ModelChoice?

    var allowedRules: Set<CorrectionRule>

    static func `default`(for language: CorrectionLanguage) -> LanguageSettings {
        LanguageSettings(
            isEnabled: language.isEnabledByDefault,
            model: nil,
            allowedRules: language.applicableRules
        )
    }
}

/**
 The settings that apply to one correction, with per-app answers resolved.

 Passed in per correction rather than fixed when a corrector is built, because
 the answers differ by app and the user is in a different app each time. Rules
 stay keyed by language, because which language a passage is in is not known
 until the passage is read.
 */
struct AppSettings: Equatable, Sendable {
    var languages: [CorrectionLanguage: LanguageSettings]

    func rules(for language: CorrectionLanguage) -> Set<CorrectionRule> {
        languages[language]?.allowedRules ?? language.applicableRules
    }

    func model(for language: CorrectionLanguage) -> ModelChoice? {
        languages[language]?.model
    }

    /** Everything allowed, for callers with no app and no preferences to ask. */
    static let permissive = AppSettings(
        languages: Dictionary(
            uniqueKeysWithValues: CorrectionLanguage.allCases.map {
                ($0, LanguageSettings(isEnabled: true, model: nil, allowedRules: $0.applicableRules))
            }
        )
    )
}
