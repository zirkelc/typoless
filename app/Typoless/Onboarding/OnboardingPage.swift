import Foundation

/**
 The steps of first-run setup, in order.

 Setup used to be one window holding everything: two permissions, a sample field
 and a Done button. That reads as a form to fill in, and the one thing it has to
 do is get two switches flipped in System Settings, in order, before anything
 else is worth looking at.

 The order is the dependency order. Nothing can be corrected until the
 permissions are granted; nothing can be detected until a language is added; the
 trigger has to exist before it can be pressed; and only then is there anything
 to try. Each step is blocked until the one before it is satisfied, so nobody
 reaches the sample field and finds that nothing happens.
 */
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case permissions
    case languages
    case triggers
    case tryIt

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Typoless"
        case .permissions: return "Let's set up permissions"
        case .languages: return "Which languages do you write in?"
        case .triggers: return "How to fix your text"
        case .tryIt: return "Try it out"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "Fixes the typos in whatever you are writing, wherever you are writing it. Everything runs on this Mac, and your text is never sent anywhere."
        case .permissions:
            return "Two things to allow. Neither can be granted from here, so each one opens System Settings."
        case .languages:
            return "The language of each line is detected, and only the languages you add are corrected."
        case .triggers:
            return "Keep either one, or both. You can change them later under Settings."
        case .tryIt:
            return "Both fields take the same path Typoless takes in any other app."
        }
    }

    /** What the button at the bottom says on this page. */
    var advanceTitle: String {
        self == Self.allCases.last ? "Finish" : "Continue"
    }

    var next: OnboardingPage? {
        OnboardingPage(rawValue: rawValue + 1)
    }

    var previous: OnboardingPage? {
        OnboardingPage(rawValue: rawValue - 1)
    }

    /** How far along the bar at the top is, counting this page as done. */
    var progress: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }
}
