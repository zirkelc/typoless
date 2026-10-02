import Foundation

/**
 Why a change did not reach the field.

 Every one of these was a log line and nothing else, which is to say it was
 visible to whoever thought to run `log stream` and to nobody else. A user whose
 text was left alone saw an app that had done nothing, and could not tell that
 from an app that was not running: the day this was written, a short line was
 dropped for being in Portuguese and the only way to find out was to read the
 log over the user's shoulder.

 So the reasons are values now. They are kept with the correction, shown in the
 history window, and carried into a bug report, where they save the one question
 that would otherwise have to be asked first.
 */
enum CorrectionRefusal: Sendable, Equatable {
    /** The model changed a word into a different word rather than fixing it. */
    case notACorrection
    /** A kind of change the user has turned off for this language. */
    case ruleTurnedOff
    /** Inside a link, a mention, a code span: text the app never edits. */
    case protectedText
    /** Not one of the languages being corrected, so the text was never sent. */
    case languageNotCorrected(CorrectionLanguage?)
    /** The reply came back in another language, which is a translation. */
    case languageChanged
    /** The reply came back in capitals. */
    case shouting
    /** More of the reply was refused than kept, so none of it was trusted. */
    case rewrite
    /** The pass ran out of time before this part of the field. */
    case outOfTime
    /**
     The model would not answer, which its safety filter does to ordinary text
     now and again. Recorded only after the second wording was turned down too.
     */
    case modelDeclined

    /** One sentence, in the words the history window and a report both use. */
    var summary: String {
        switch self {
        case .notACorrection:
            return "Not a correction: the word became a different word."
        case .ruleTurnedOff:
            return "This kind of change is turned off."
        case .protectedText:
            return "Inside text Typoless never changes."
        case .languageNotCorrected(let detected):
            guard let detected else {
                return "Not in a language Typoless corrects."
            }

            return "Read as \(detected.displayName), which is not switched on."
        case .languageChanged:
            return "The reply came back in another language."
        case .shouting:
            return "The reply came back in capitals."
        case .rewrite:
            return "The model rewrote the text rather than correcting it."
        case .outOfTime:
            return "The pass ran out of time."
        case .modelDeclined:
            return "The model would not answer this text."
        }
    }
}

/**
 One thing that happened to one piece of text.

 Applied or refused, both are kept: what the app did is only half of what a user
 needs to report a problem, and the other half is what it decided not to do.
 */
struct CorrectionNote: Sendable, Equatable, Identifiable {
    let id = UUID()
    /** The text as the user wrote it. */
    let before: String
    /** What it would have become, or nil where the model was never asked. */
    let after: String?
    /** Nil where the change was made. */
    let refusal: CorrectionRefusal?

    var isApplied: Bool { refusal == nil }

    /**
     Compared by what it says, not by which object it is.

     The identifier exists for SwiftUI, which needs one per row, and the
     synthesised equality would have folded it in: two identical notes would
     then never be equal, which is a surprise waiting in whatever asks.
     */
    static func == (lhs: CorrectionNote, rhs: CorrectionNote) -> Bool {
        lhs.before == rhs.before && lhs.after == rhs.after && lhs.refusal == rhs.refusal
    }

    init(before: String, after: String?, refusal: CorrectionRefusal? = nil) {
        self.before = before
        self.after = after
        self.refusal = refusal
    }

    /** How it reads in a report: an arrow for a change, a dash for text never sent. */
    var description: String {
        guard let after else { return before }

        return "\(before) → \(after)"
    }
}

/**
 What one pass decided, beside the edits it produced.

 Gathered as the pipeline runs rather than reconstructed afterwards, because
 most of it cannot be reconstructed: once a chunk is skipped there is nothing
 left in the result to say it existed.
 */
struct CorrectionOutcome: Sendable, Equatable {
    /** Which languages were corrected, in the order they were first read. */
    var languages: [CorrectionLanguage] = []

    /** Every change offered, applied or not, and every piece of text left alone. */
    var notes: [CorrectionNote] = []

    var appliedCount: Int { notes.count(where: \.isApplied) }

    mutating func add(language: CorrectionLanguage) {
        guard !languages.contains(language) else { return }

        languages.append(language)
    }

    mutating func add(_ note: CorrectionNote) {
        notes.append(note)
    }
}
