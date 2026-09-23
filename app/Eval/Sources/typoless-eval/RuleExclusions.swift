import Foundation

/**
 What to tell the model about a rule the user has switched off.

 The app says nothing today: a rule that is off is filtered out of the edits
 afterwards, and the model is asked the same question either way. Two things
 make that worth measuring. With strict mode off nothing filters at all, so a
 rule that is off means nothing whatsoever. And with strict mode on an edit is
 classified as a set, so a change that restores an umlaut *and* adds a comma is
 skipped whole when commas are off, taking a wanted fix with it.

 Against that stands the strongest finding the sweeps produced: for a model this
 small, naming a rule usually costs more than it buys, and the naming that cost
 most was a rule about capitals. So this is a candidate, not a design.

 One sentence per rule, in the language of the text, phrased as an order,
 because both of those are what measured well for the rules the app does want.
 */
enum RuleExclusions {
    /**
     The sentence that forbids one rule, or nil where the language has no such
     rule to forbid.
     */
    static func sentence(for rule: CorrectionRule, in language: CorrectionLanguage) -> String? {
        guard language.applicableRules.contains(rule) else { return nil }

        switch language {
        case .german: return german(rule)
        default: return english(rule)
        }
    }

    /**
     Everything to append to the instructions, or an empty string when nothing
     is switched off.

     Ordered by the rules as the language declares them, so the wording for a
     given set of switches is the same on every run.
     */
    static func text(for rules: Set<CorrectionRule>, in language: CorrectionLanguage) -> String {
        let sentences = language.rules
            .map(\.rule)
            .filter(rules.contains)
            .compactMap { sentence(for: $0, in: language) }

        guard !sentences.isEmpty else { return "" }

        return " " + sentences.joined(separator: " ")
    }

    private static func english(_ rule: CorrectionRule) -> String {
        switch rule {
        case .spacing: return "Do not change spaces."
        case .capitalisation: return "Do not change the capital letter a sentence starts with."
        case .nounCapitalisation: return "Do not put a capital letter inside a sentence."
        case .commas: return "Do not add or remove commas."
        case .sentenceEndings: return "Do not add a full stop, question mark or exclamation mark at the end."
        case .otherPunctuation: return "Do not change any other punctuation mark."
        case .apostrophes: return "Do not add or remove apostrophes."
        case .umlauts: return "Do not add accents."
        case .typos: return "Do not correct spelling."
        case .grammar: return "Do not change the form of a word."
        }
    }

    private static func german(_ rule: CorrectionRule) -> String {
        switch rule {
        case .spacing: return "Ändere keine Abstände."
        case .capitalisation: return "Ändere den ersten Buchstaben eines Satzes nicht."
        case .nounCapitalisation: return "Schreibe nichts innerhalb eines Satzes groß."
        case .commas: return "Setze und entferne keine Kommas."
        case .sentenceEndings: return "Setze am Ende keinen Punkt, kein Fragezeichen und kein Ausrufezeichen."
        case .otherPunctuation: return "Ändere keine anderen Satzzeichen."
        case .apostrophes: return "Setze und entferne keine Apostrophe."
        case .umlauts: return "Lasse ae, oe, ue und ss so stehen, wie sie geschrieben sind."
        case .typos: return "Korrigiere keine Rechtschreibung."
        case .grammar: return "Ändere keine Wortformen."
        }
    }
}
