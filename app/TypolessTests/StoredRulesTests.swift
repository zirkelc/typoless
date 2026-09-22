import Foundation
import Testing
@testable import Typoless

/**
 A rule added in a later version starts on.

 Rules are stored as the set that is allowed, so a rule the stored set has
 never heard of would otherwise read as one the user turned off.
 */
@MainActor
struct StoredRulesTests {
    /** A private suite, so the tests never read or write the app's real settings. */
    private func defaults() -> UserDefaults {
        let name = "StoredRulesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func `grammar starts on for rules stored before it existed`() {
        // Arrange
        let defaults = defaults()
        let before = CorrectionLanguage.german.applicableRules.subtracting([.grammar, .commas])
        defaults.set(
            [CorrectionLanguage.german.rawValue: ["enabled": true, "rules": before.map(\.rawValue)]],
            forKey: DefaultsKey.languageSettings
        )

        // Act
        let rules = Preferences(defaults: defaults).languageSettings[.german]?.allowedRules

        // Assert
        #expect(rules == before.union([.grammar]))
    }

    @Test func `grammar stays off once it was turned off`() {
        // Arrange
        let defaults = defaults()
        let allowed = CorrectionLanguage.german.applicableRules.subtracting([.grammar])
        defaults.set(
            [
                CorrectionLanguage.german.rawValue: [
                    "enabled": true,
                    "rules": allowed.map(\.rawValue),
                    "known": CorrectionLanguage.german.applicableRules.map(\.rawValue),
                ],
            ],
            forKey: DefaultsKey.languageSettings
        )

        // Act
        let rules = Preferences(defaults: defaults).languageSettings[.german]?.allowedRules

        // Assert
        #expect(rules == allowed)
    }
}
