import Foundation

/**
 The settings that apply to one correction, with per-app answers resolved.

 Passed in per correction rather than fixed when a corrector is built, because
 the answers can differ by app: a full stop is right in an email and changes the
 tone of a chat line, and the user is in a different app each time.
 */
struct AppSettings: Equatable, Sendable {
    var allowedKinds: Set<EditKind>
    var addsSentenceFinalPunctuation: Bool

    /** Everything allowed, for callers with no app to ask about. */
    static let permissive = AppSettings(
        allowedKinds: Set(EditKind.allCases),
        addsSentenceFinalPunctuation: true
    )
}
