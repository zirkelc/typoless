import NaturalLanguage

/** A language the app knows how to correct. */
enum CorrectionLanguage: String, CaseIterable, Sendable {
    case english
    case german

    var displayName: String {
        switch self {
        case .english: return "English"
        case .german: return "German"
        }
    }

    var nlLanguage: NLLanguage {
        switch self {
        case .english: return .english
        case .german: return .german
        }
    }

    /**
     What the model is told before it sees the text, in the language of the text.

     Instructing the model in English about German text makes it noticeably
     shy: it fixes the obvious misspellings and then leaves sentence
     capitalisation, missing umlauts and missing commas alone. The same request
     written in German, naming the rules that language actually has, recovers
     all three.

     This wording is tuned by measurement rather than taste. Changing it is
     fine, but check the result on real text afterwards, because small edits
     here move the model's behaviour more than they look like they should.
     */
    var instructions: String {
        switch self {
        case .english:
            return """
            You correct text that someone has already written.

            You fix only these things: spelling mistakes, missing or wrong \
            punctuation, capitalisation, and spacing.

            You never rephrase, reword, translate, shorten, expand, or improve \
            the writing. You never add or remove a word. You never change the \
            tone or the meaning. If the text is already correct, you return it \
            exactly as it is.
            """
        case .german:
            return """
            Du korrigierst Texte, die jemand bereits geschrieben hat.

            Du korrigierst ausschliesslich:
            - Rechtschreibfehler, auch fehlende Umlaute (ae, oe, ue, ss werden \
            zu ä, ö, ü, ß, wenn das Wort es verlangt)
            - fehlende oder falsche Satzzeichen, besonders das Komma vor \
            Nebensaetzen (dass, ob, weil, wenn, der, die, das)
            - Gross- und Kleinschreibung: jeder Satz beginnt gross, und jedes \
            Substantiv wird grossgeschrieben
            - Abstaende

            Du formulierst nichts um, uebersetzt nichts, kuerzt nichts und \
            fuegst kein Wort hinzu und entfernst keines. Du aenderst weder Ton \
            noch Bedeutung.
            """
        }
    }

    func prompt(for text: String) -> String {
        switch self {
        case .english:
            return "Correct this English text, keeping every word:\n\n\(text)"
        case .german:
            return "Korrigiere diesen deutschen Text und behalte jedes Wort:\n\n\(text)"
        }
    }
}

/**
 Works out which language a passage is in.

 Constrained to the languages the user has enabled rather than open-ended, since
 a short message is easy to mistake for a neighbouring language and the only
 cost of a wrong answer is a worse correction. Detection runs per chunk because
 mixing English and German inside one message is normal for the people this app
 is for.
 */
struct LanguageDetector: Sendable {
    let enabled: [CorrectionLanguage]

    init(enabled: [CorrectionLanguage] = CorrectionLanguage.allCases) {
        self.enabled = enabled.isEmpty ? CorrectionLanguage.allCases : enabled
    }

    func detect(_ text: String) -> CorrectionLanguage {
        guard enabled.count > 1 else { return enabled[0] }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = enabled.map(\.nlLanguage)
        recognizer.processString(text)

        guard
            let dominant = recognizer.dominantLanguage,
            let match = enabled.first(where: { $0.nlLanguage == dominant })
        else {
            return enabled[0]
        }

        return match
    }
}
