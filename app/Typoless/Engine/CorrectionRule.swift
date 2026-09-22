import Foundation

/**
 One kind of change the app is allowed to make.

 Finer than the four kinds this replaces, because the four were a description of
 what the classifier could tell apart rather than of anything a person wants to
 decide. "Punctuation" bundled the comma someone forgot with the full stop they
 left off on purpose, and those are not the same question.

 Which rules exist is the same everywhere; which of them mean anything depends
 on the language. Restoring an umlaut is a German question and an apostrophe is
 mostly an English one, so each language declares the rules it has and gives an
 example of each in its own words.
 */
enum CorrectionRule: String, CaseIterable, Sendable {
    case spacing
    case capitalisation
    case nounCapitalisation
    case commas
    case sentenceEndings
    case otherPunctuation
    case apostrophes
    case umlauts
    case typos
    /**
     A real word put into the form the sentence needs: "wegen dem Termin" to
     "wegen des Termins", "she go" to "she goes". Only the ending of the word
     changes, and the word it starts from has to be in the dictionary, which is
     what keeps a typo at the end of a word out of this rule.
     */
    case grammar

    var displayName: String {
        switch self {
        case .spacing: return "Spacing"
        case .capitalisation: return "Sentence capitals"
        case .nounCapitalisation: return "Noun capitals"
        case .commas: return "Commas"
        case .sentenceEndings: return "Sentence endings"
        case .otherPunctuation: return "Other punctuation"
        case .apostrophes: return "Apostrophes"
        case .umlauts: return "Umlauts"
        case .typos: return "Typos"
        case .grammar: return "Grammar"
        }
    }

    /**
     Whether this may fire without the model being asked for it.

     Sentence endings are the one rule that is off for some people everywhere
     and on for others, because a message that stops without a full stop is not
     a mistake and in a chat a full stop changes the tone. It is the largest
     single source of changes nobody asked for, so it starts on and is the first
     thing worth turning off.
     */
    var isEnabledByDefault: Bool { true }
}

/** A rule in one language: whether it applies, and what it looks like there. */
struct RuleExample: Sendable {
    let rule: CorrectionRule
    let before: String
    let after: String
}
