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

 The trigger comes before the permissions, which is the one place the order is
 not a dependency. It is what the app does, and it costs the reader nothing. A
 window that opens and asks for accessibility on its second breath has not yet
 said what it wants it for.
 */
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case triggers
    case permissions
    case languages
    case tryIt
    case history

    var id: Int { rawValue }

    /**
     The first page carries the icon and no card, so it is laid out down the
     middle of the window rather than from the top of it.
     */
    var isHero: Bool { self == .welcome }

    var title: String {
        switch self {
        case .welcome: return "Welcome to Typoless"
        case .triggers: return "How Typoless works"
        case .permissions: return "Typoless needs two permissions"
        case .languages: return "Which languages do you write in?"
        case .tryIt: return "Try it out"
        case .history: return "If it gets something wrong"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "Fixes the typos in the text you are writing, in any app. Everything runs on this Mac, so your text never leaves it."
        case .triggers:
            return "Keep either way to start a correction, or both. You can change them later in Settings."
        case .permissions:
            return "You cannot grant either from here, so each button opens System Settings."
        case .languages:
            return "Typoless detects the language of each line, and corrects only the languages you add."
        case .tryIt:
            return "Typoless corrects these fields exactly as it does in any other app."
        case .history:
            return "Every correction can be undone, and the ones you just made are below."
        }
    }

    /** What the button at the bottom says on this page. */
    var advanceTitle: String {
        if self == .welcome { return "Get Started" }

        return self == Self.allCases.last ? "Finish" : "Continue"
    }

    var next: OnboardingPage? {
        OnboardingPage(rawValue: rawValue + 1)
    }

    var previous: OnboardingPage? {
        OnboardingPage(rawValue: rawValue - 1)
    }
}
