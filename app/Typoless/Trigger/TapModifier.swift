import AppKit

/** A modifier key that can be tapped twice to start a correction. */
enum TapModifier: String, CaseIterable, Sendable {
    case command
    case option
    case control
    case shift

    var displayName: String {
        switch self {
        case .command: return "⌘ Command"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .shift: return "⇧ Shift"
        }
    }

    /** The symbol alone, for prose that already says what it is. */
    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }

    /**
     What to warn about, if anything.

     Shift is the one that earns a caution: it is held down for every capital
     letter, so it is tapped far more often than the others in the ordinary
     course of typing, and the guard against that is only as good as the
     keystroke counting behind it.
     */
    var caution: String? {
        switch self {
        case .shift:
            return "Shift is pressed for every capital letter, so this fires more easily by accident than the others."
        case .command, .option, .control:
            return nil
        }
    }
}
