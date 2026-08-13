import NaturalLanguage

/**
 A language the app knows how to correct.

 Two of these are tuned by measurement and the rest are not, which is recorded
 in `isTuned` rather than left for someone to discover. The eval covers English
 and German; anything else uses instructions built from the same template and
 has never been scored, so it is offered but not promised.
 */
enum CorrectionLanguage: String, CaseIterable, Sendable, Identifiable {
    case english
    case german
    case french
    case spanish
    case italian
    case dutch
    case portuguese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .german: return "German"
        case .french: return "French"
        case .spanish: return "Spanish"
        case .italian: return "Italian"
        case .dutch: return "Dutch"
        case .portuguese: return "Portuguese"
        }
    }

    var nlLanguage: NLLanguage {
        switch self {
        case .english: return .english
        case .german: return .german
        case .french: return .french
        case .spanish: return .spanish
        case .italian: return .italian
        case .dutch: return .dutch
        case .portuguese: return .portuguese
        }
    }

    /** Whether the wording below has been scored against a dataset. */
    var isTuned: Bool {
        switch self {
        case .english, .german: return true
        case .french, .spanish, .italian, .dutch, .portuguese: return false
        }
    }

    /** On unless the user says otherwise, so the app works out of the box. */
    var isEnabledByDefault: Bool {
        self == .english || self == .german
    }

    /**
     The rules that mean anything in this language, in the order they are shown.

     An apostrophe is mostly an English problem, umlauts and capitalised nouns
     are German ones, and offering either where it does not apply is a row the
     user has to read and dismiss for the life of the app.
     */
    var rules: [RuleExample] {
        switch self {
        case .english:
            return [
                RuleExample(rule: .typos, before: "teh meeting", after: "the meeting"),
                RuleExample(rule: .capitalisation, before: "hello there", after: "Hello there"),
                RuleExample(rule: .apostrophes, before: "its ready", after: "it's ready"),
                RuleExample(rule: .commas, before: "well done everyone", after: "well done, everyone"),
                RuleExample(rule: .sentenceEndings, before: "see you tomorrow", after: "see you tomorrow."),
                RuleExample(rule: .otherPunctuation, before: "really?!", after: "really?"),
                RuleExample(rule: .spacing, before: "hello  world", after: "hello world"),
            ]
        case .german:
            return [
                RuleExample(rule: .typos, before: "der Termn", after: "der Termin"),
                RuleExample(rule: .umlauts, before: "gruesse", after: "grüße"),
                RuleExample(rule: .capitalisation, before: "hallo zusammen", after: "Hallo zusammen"),
                RuleExample(rule: .nounCapitalisation, before: "ein test", after: "ein Test"),
                RuleExample(rule: .commas, before: "ich hoffe dass es passt", after: "ich hoffe, dass es passt"),
                RuleExample(rule: .sentenceEndings, before: "bis morgen", after: "bis morgen."),
                RuleExample(rule: .otherPunctuation, before: "wirklich?!", after: "wirklich?"),
                RuleExample(rule: .spacing, before: "hallo  welt", after: "hallo welt"),
            ]
        case .french:
            return [
                RuleExample(rule: .typos, before: "le rendez-vus", after: "le rendez-vous"),
                RuleExample(rule: .capitalisation, before: "bonjour à tous", after: "Bonjour à tous"),
                RuleExample(rule: .apostrophes, before: "j ai compris", after: "j'ai compris"),
                RuleExample(rule: .commas, before: "si tu peux dis-moi", after: "si tu peux, dis-moi"),
                RuleExample(rule: .sentenceEndings, before: "à demain", after: "à demain."),
                RuleExample(rule: .otherPunctuation, before: "vraiment?!", after: "vraiment ?"),
                RuleExample(rule: .spacing, before: "bonjour  à tous", after: "bonjour à tous"),
            ]
        case .spanish:
            return [
                RuleExample(rule: .typos, before: "la reunon", after: "la reunión"),
                RuleExample(rule: .capitalisation, before: "hola a todos", after: "Hola a todos"),
                RuleExample(rule: .commas, before: "si puedes avísame", after: "si puedes, avísame"),
                RuleExample(rule: .sentenceEndings, before: "hasta mañana", after: "hasta mañana."),
                RuleExample(rule: .otherPunctuation, before: "de verdad?", after: "¿de verdad?"),
                RuleExample(rule: .spacing, before: "hola  a todos", after: "hola a todos"),
            ]
        case .italian:
            return [
                RuleExample(rule: .typos, before: "la riunone", after: "la riunione"),
                RuleExample(rule: .capitalisation, before: "ciao a tutti", after: "Ciao a tutti"),
                RuleExample(rule: .apostrophes, before: "l idea", after: "l'idea"),
                RuleExample(rule: .commas, before: "se puoi fammi sapere", after: "se puoi, fammi sapere"),
                RuleExample(rule: .sentenceEndings, before: "a domani", after: "a domani."),
                RuleExample(rule: .otherPunctuation, before: "davvero?!", after: "davvero?"),
                RuleExample(rule: .spacing, before: "ciao  a tutti", after: "ciao a tutti"),
            ]
        case .dutch:
            return [
                RuleExample(rule: .typos, before: "de vergaderng", after: "de vergadering"),
                RuleExample(rule: .capitalisation, before: "hallo allemaal", after: "Hallo allemaal"),
                RuleExample(rule: .apostrophes, before: "s morgens", after: "'s morgens"),
                RuleExample(rule: .commas, before: "als je kunt laat het weten", after: "als je kunt, laat het weten"),
                RuleExample(rule: .sentenceEndings, before: "tot morgen", after: "tot morgen."),
                RuleExample(rule: .otherPunctuation, before: "echt?!", after: "echt?"),
                RuleExample(rule: .spacing, before: "hallo  allemaal", after: "hallo allemaal"),
            ]
        case .portuguese:
            return [
                RuleExample(rule: .typos, before: "a reunio", after: "a reunião"),
                RuleExample(rule: .capitalisation, before: "olá a todos", after: "Olá a todos"),
                RuleExample(rule: .commas, before: "se puderes avisa-me", after: "se puderes, avisa-me"),
                RuleExample(rule: .sentenceEndings, before: "até amanhã", after: "até amanhã."),
                RuleExample(rule: .otherPunctuation, before: "a sério?!", after: "a sério?"),
                RuleExample(rule: .spacing, before: "olá  a todos", after: "olá a todos"),
            ]
        }
    }

    /** The rules this language has anything to say about. */
    var applicableRules: Set<CorrectionRule> {
        Set(rules.map(\.rule))
    }

    /**
     What the model is told before it sees the text, in the language of the text.

     Instructing the model in English about German text makes it noticeably
     shy: it fixes the obvious misspellings and then leaves sentence
     capitalisation, missing umlauts and missing commas alone. The same request
     written in German, naming the rules that language actually has, recovers
     all three.

     The exception comes first and the rules come last, which is not
     presentation. Measured over the eval datasets, the same exception moved to
     the end costs the on-device model most of its sentence-initial capitals in
     German: it reads "leave this exactly as it is" as advice about the whole
     text rather than about the spans named, and whatever is said last is what
     it does. Restating the capitalisation rule after the exception did not
     recover it; moving the exception above the rules did.

     The exception is worth having even though the guardrail already vetoes
     edits inside those spans. A refused edit counts against the chunk, and a
     chunk that has more refused than accepted is dropped whole, so a model that
     never proposes the edit keeps the corrections around it.

     English and German are tuned by measurement rather than taste. Changing
     either is fine, but re-run `Eval/` afterwards, because small edits here move
     the model's behaviour more than they look like they should. The rest are
     built from the English wording and have never been scored.
     */
    var instructions: String {
        switch self {
        case .english:
            return """
            Web addresses, email addresses, @handles, #channels, text in \
            backticks and emoji are copied across character for character, \
            however wrong they look.

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
            Internetadressen, E-Mail-Adressen, @Namen, #Kanaele, Text in \
            Backticks und Emojis uebernimmst du Zeichen fuer Zeichen, egal \
            wie falsch sie aussehen.

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
        case .french, .spanish, .italian, .dutch, .portuguese:
            /**
             Built from the English wording, in English, and never scored. The
             German result says instructing a model in the text's own language
             is worth several points, so this is the weaker of the two options,
             and it is used only because writing the other one well needs
             someone who speaks the language.
             */
            return """
            Web addresses, email addresses, @handles, #channels, text in \
            backticks and emoji are copied across character for character, \
            however wrong they look.

            You correct \(displayName) text that someone has already written.

            You fix only these things: spelling mistakes, missing or wrong \
            accents, missing or wrong punctuation, capitalisation, and spacing.

            You never rephrase, reword, translate, shorten, expand, or improve \
            the writing. You never add or remove a word. You never change the \
            tone or the meaning. If the text is already correct, you return it \
            exactly as it is.
            """
        }
    }

    func prompt(for text: String) -> String {
        switch self {
        case .english:
            return "Correct this English text, keeping every word:\n\n\(text)"
        case .german:
            return "Korrigiere diesen deutschen Text und behalte jedes Wort:\n\n\(text)"
        default:
            return "Correct this \(displayName) text, keeping every word:\n\n\(text)"
        }
    }
}

/**
 Works out which language a passage is in.

 Constrained to the languages the user has enabled rather than open-ended, since
 a short message is easy to mistake for a neighbouring language and the only
 cost of a wrong answer is a worse correction. Detection runs per chunk because
 mixing languages inside one message is normal for the people this app is for.
 */
struct LanguageDetector: Sendable {
    let enabled: [CorrectionLanguage]

    init(enabled: [CorrectionLanguage] = CorrectionLanguage.allCases.filter(\.isEnabledByDefault)) {
        self.enabled = enabled.isEmpty ? [.english] : enabled
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
