import Testing
@testable import Typoless

/** Which apps may be read at all. */
struct AppPolicyTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let policy: AppPolicy
        let bundleID: String?
        let expected: Bool

        var testDescription: String { name }
    }

    /** Exclusions only: everything passes but the apps named. */
    static let excludingOnly = AppPolicy(denied: ["com.apple.Terminal"], allowed: [])

    /** Naming even one app to include narrows everything else out. */
    static let narrowed = AppPolicy(denied: ["com.apple.Terminal"], allowed: ["com.apple.Mail"])

    /** The point of the two-table split: exclusion wins, whatever the other list says. */
    static let contradicting = AppPolicy(denied: ["com.apple.Terminal"], allowed: ["com.apple.Terminal"])

    /** A seeded exclusion has to survive an inclusion list drawn up around it. */
    static let seededPlusIncludes = AppPolicy(
        denied: AppPolicy.defaultDenied,
        allowed: ["com.apple.dt.Xcode", "com.apple.Mail"]
    )

    static let cases: Array<Case> = [
        Case(name: "an unnamed app passes", policy: excludingOnly, bundleID: "com.apple.Safari", expected: true),
        Case(name: "an excluded app does not", policy: excludingOnly, bundleID: "com.apple.Terminal", expected: false),
        Case(name: "no identifier passes while nothing is included", policy: excludingOnly, bundleID: nil, expected: true),
        Case(name: "an included app passes", policy: narrowed, bundleID: "com.apple.Mail", expected: true),
        Case(name: "an app that is neither does not", policy: narrowed, bundleID: "com.apple.Safari", expected: false),
        Case(name: "no identifier does not, once anything is included", policy: narrowed, bundleID: nil, expected: false),
        Case(
            name: "including an excluded app does not readmit it",
            policy: contradicting,
            bundleID: "com.apple.Terminal",
            expected: false
        ),
        Case(
            name: "and does not readmit anything else either",
            policy: contradicting,
            bundleID: "com.apple.Mail",
            expected: false
        ),
        Case(
            name: "a seeded exclusion outranks being included",
            policy: seededPlusIncludes,
            bundleID: "com.apple.dt.Xcode",
            expected: false
        ),
        Case(
            name: "while the rest of that list still works",
            policy: seededPlusIncludes,
            bundleID: "com.apple.Mail",
            expected: true
        ),
    ]

    @Test(arguments: cases)
    func `the policy permits only what it should`(_ row: Case) {
        // Arrange
        let policy = row.policy

        // Act
        let permitted = policy.permits(row.bundleID)

        // Assert
        #expect(permitted == row.expected)
    }

    /** Every seeded exclusion has to actually be excluded, or the seed is decorative. */
    @Test(arguments: AppPolicy.defaultDenied.sorted())
    func `excluded by default`(_ bundleID: String) {
        // Arrange
        let seeded = AppPolicy()

        // Act
        let permitted = seeded.permits(bundleID)

        // Assert
        #expect(permitted == false)
    }

    struct ReasonCase: Sendable, CustomTestStringConvertible {
        let name: String
        let policy: AppPolicy
        let bundleID: String?
        let expected: AppPolicy.Decision

        var testDescription: String { name }
    }

    static let reasonCases: Array<ReasonCase> = [
        ReasonCase(name: "an excluded app reports exclusion", policy: narrowed, bundleID: "com.apple.Terminal", expected: .excluded),
        ReasonCase(name: "an app left out reports omission", policy: narrowed, bundleID: "com.apple.Safari", expected: .notIncluded),
        ReasonCase(
            name: "exclusion is reported ahead of omission",
            policy: contradicting,
            bundleID: "com.apple.Terminal",
            expected: .excluded
        ),
    ]

    /** The reason given has to match, since one is spoken aloud and the other is not. */
    @Test(arguments: reasonCases)
    func `the decision gives the right reason`(_ row: ReasonCase) {
        // Arrange
        let policy = row.policy

        // Act
        let decision = policy.decision(for: row.bundleID)

        // Assert
        #expect(decision == row.expected)
    }
}
