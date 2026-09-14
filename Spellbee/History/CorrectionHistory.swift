import Foundation
import Observation

/**
 How long a correction stays recoverable.

 Every option is bounded by quitting, since none of this is written to disk, so
 the longest one says exactly that rather than naming a number it cannot keep.
 */
enum HistoryRetention: String, CaseIterable, Identifiable, Sendable {
    case off
    case oneHour
    case threeHours
    case eightHours
    case untilQuit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Keep nothing"
        case .oneHour: return "1 hour"
        case .threeHours: return "3 hours"
        case .eightHours: return "8 hours"
        case .untilQuit: return "Until Spellbee quits"
        }
    }

    /** Nil where nothing ages out on a clock. */
    var duration: TimeInterval? {
        switch self {
        case .off, .untilQuit: return nil
        case .oneHour: return 60 * 60
        case .threeHours: return 3 * 60 * 60
        case .eightHours: return 8 * 60 * 60
        }
    }

    var keepsHistory: Bool { self != .off }

    /** What the history window says about itself, in its own words. */
    var footnote: String {
        switch self {
        case .off:
            return "History is turned off."
        case .untilQuit:
            return "Kept until Spellbee quits. Never written to disk."
        case .oneHour, .threeHours, .eightHours:
            return "Kept in memory for \(displayName), then dropped. Never written to disk."
        }
    }
}

/**
 What Spellbee changed recently, kept so a bad correction can be undone by hand.

 Undo covers the correction you have just watched happen. This covers the one you
 notice three messages later, and the one where the field took a write that
 flattened more than it fixed.

 **Held in memory and never written to disk.** This is the one part of the app
 that keeps the text itself rather than a count of characters, which is exactly
 what the rest of it promises not to do. A file would turn a safety net into a
 plaintext record of everything the user typed, surviving long after the moment
 it was useful for, and readable by anything that can read their home directory.
 So it lives for as long as the user asks and dies with the process.
 */
@MainActor
@Observable
final class CorrectionHistory {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let bundleID: String?
        /**
         The whole field either side of the correction, not just the part that
         changed, because putting it back is the point and a fragment cannot.
         */
        let before: String
        let after: String
        let editCount: Int
    }

    /**
     Set from preferences, and applied the moment it changes rather than at the
     next correction, since shortening it is something people do because they
     want what is already there gone.
     */
    var retention: HistoryRetention = .threeHours {
        didSet {
            guard retention != oldValue else { return }

            if !retention.keepsHistory { entries.removeAll() }

            prune()
        }
    }

    /**
     A ceiling as well as an age, so that a busy hour cannot hold an unbounded
     amount of someone's writing in memory. It is the only bound on the longest
     retention setting.
     */
    private static let limit = 50

    private(set) var entries: [Entry] = []

    func record(before: String, after: String, bundleID: String?, editCount: Int) {
        guard retention.keepsHistory, before != after else { return }

        entries.insert(
            Entry(
                date: Date(),
                bundleID: bundleID,
                before: before,
                after: after,
                editCount: editCount
            ),
            at: 0
        )

        prune()
    }

    /**
     Drops whatever has aged out.

     Called when the history is shown as well as when it grows, since entries
     expire on a clock that nothing here is watching.
     */
    func prune() {
        if let duration = retention.duration {
            let cutoff = Date().addingTimeInterval(-duration)
            entries.removeAll { $0.date < cutoff }
        }

        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
    }

    func clear() {
        entries.removeAll()
    }
}
