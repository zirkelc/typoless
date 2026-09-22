/** What the menu bar icon is currently telling the user. */
enum AppStatus: Equatable {
    /** Ready and waiting for a trigger. */
    case idle
    /** A correction pass is running. */
    case working
    /** Deliberately switched off by the user. */
    case paused
    /** A permission is missing or the model is unavailable. */
    case needsAttention
    /** Model weights are being fetched, with progress from 0 to 1. */
    case downloading(Double)

    var symbolName: String {
        switch self {
        case .idle: return "textformat.abc"
        case .working: return "sparkles"
        case .paused: return "pause.circle"
        case .needsAttention: return "exclamationmark.triangle.fill"
        case .downloading: return "arrow.down.circle"
        }
    }

    var label: String {
        switch self {
        case .idle: return "Typoless is ready"
        case .working: return "Typoless is correcting"
        case .paused: return "Typoless is paused"
        case .needsAttention: return "Typoless needs setup"
        case .downloading(let progress):
            guard let percentage = Self.percentage(progress) else { return "Downloading model" }
            return "Downloading model, \(percentage)"
        }
    }

    /**
     Text shown beside the icon in the menu bar.

     Only downloading earns it: a percentage is worth the width because the
     download takes minutes and is otherwise indistinguishable from a hang.
     */
    var badge: String? {
        guard case .downloading(let progress) = self else { return nil }
        return Self.percentage(progress) ?? "…"
    }

    /**
     Nil until there is something real to show.

     A download reports nothing until the first bytes of the first file land,
     and a percentage frozen at zero reads as a failure, where an ellipsis
     reads as waiting.
     */
    static func percentage(_ progress: Double) -> String? {
        guard progress > 0.001 else { return nil }
        return "\(Int(progress * 100))%"
    }
}
