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
                /**
                 English does not capitalise nouns as a class, so this was left
                 out. But the classifier judges a capital by *where* it sits,
                 not by knowing what the word is, and every mid-sentence capital
                 lands under this rule. Without it English could never capitalise
                 a name, a weekday, a month or a place.
                 */
                RuleExample(rule: .nounCapitalisation, before: "i work at google", after: "I work at Google"),
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
    /**
     What a rule is called in this language.

     The same test answers a different question depending on the language. A
     capital in the middle of a German sentence is usually an ordinary noun,
     which is a rule German has and some people do not want applied. In English
     it is almost always a name or a place. Calling both "noun capitals" was
     accurate for German and meaningless everywhere else.

     Asked of the language rather than of the rule, so the rule does not have to
     know every language there is.
     */
    func label(for rule: CorrectionRule) -> String {
        switch (rule, self) {
        case (.nounCapitalisation, .german): return "Noun capitals"
        case (.nounCapitalisation, _): return "Names and places"
        default: return rule.displayName
        }
    }

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
    /**
     What the model is told before it sees the text.

     Short on purpose, and the shortness is the finding rather than a matter of
     taste. Fourteen wordings were scored against 168 real messages: the two
     briefest came first and second, and the wording this replaces came last of
     the fourteen. Every long rule list did worse at the very rule it spelled
     out most carefully. One candidate gave a whole bullet to capitalising the
     opening word and managed it four times in forty-one, half of what the old
     wording achieved without mentioning it at all. For a model this small a
     rule buried among thirty others is worse than no rule, so anything added
     here has to earn its place against `Eval/`, not against intuition.

     Nothing is said about links, handles or code any more. `MaskedText`
     replaces them with markers before the model is asked, so there is nothing
     left for an instruction to protect.

     - Parameter startsText: Whether this chunk opens the field. A long message
       is corrected chunk by chunk, and the opening-capital rule read as true of
       every chunk, so the second paragraph of a German letter had `anbei`
       capitalised mid-sentence. Only the chunk that really is the beginning is
       told about the beginning.
     */
    /**
     English opens with an order rather than a description of the result.

     "Start the text with a capital letter" against "Capitalise the first word of
     the text" is worth 4 English cases of 86, 64 to 68, with German untouched.
     The gain is specific to that sentence rather than to imperatives: the
     equally imperative "Capitalise the first word." gains nothing, which is
     reason to hold it loosely.

     It costs a negative, knowingly. The model that capitalises more openings
     also capitalises `cc @sarah` into `CC @sarah` and starts a new capital after
     an emoji. Three attempts to keep the gain without the cost all failed, and
     the one that told it to leave the other capitals alone lost 5 cases and
     raised unrequested changes by half, which is what naming a second rule keeps
     doing to this model. Chris took the trade: four corrections against one
     message altered that was already right.
     */
    /**
     German names the ae/oe/ue/ss substitution on purpose.

     Writing the instructions with real umlauts instead of ASCII changes nothing
     at all, 48 of 82 either way, which is what an earlier sweep found and what
     three separate proposals to do it predicted wrongly. What works is one
     sentence saying what to do with the substitution: 48 to 54, and 112 to 118
     over both languages, with negatives held at 36 of 36 and fewer unrequested
     changes. The gains land exactly on the failures it names.

     That is not a general licence to name rules. The same sweep tried naming
     the German noun-capital rule and it lost 16 cases and four negatives, by
     capitalising everything in sight. A mechanical substitution the model can
     simply apply is worth naming; a judgement it has to exercise is not.
     */
    func instructions(startsText: Bool = true) -> String {
        switch self {
        case .english:
            return """
            Fix spelling, punctuation, capitalisation and spacing. Change \
            nothing else.
            """ + (startsText ? " Start the text with a capital letter." : "")
        case .german:
            return """
            Korrigiere Rechtschreibung, Satzzeichen, Groß- und \
            Kleinschreibung und Abstände. Schreibe ae, oe, ue und ss als ä, ö, \
            ü und ß. Ändere sonst nichts.
            """ + (startsText ? " Das erste Wort des Textes wird großgeschrieben." : "")
        /**
         Built from the English wording and never scored, since only English and
         German have datasets. Naming the language is worth several points in
         German, so the same is assumed here.
         */
        case .french, .spanish, .italian, .dutch, .portuguese:
            return """
            Fix spelling, accents, punctuation, capitalisation and spacing in \
            this \(displayName) text. Change nothing else.
            """ + (startsText ? " Start the text with a capital letter." : "")
        }
    }

    /**
     The turn that carries the text.

     The two languages want opposite things here, which is why they no longer
     share a shape. German gains seven cases from the bare imperative and
     English loses four from it, measured twice: once on the tuning set and
     again on all 168 with the same size and sign. Naming the language in the
     turn buys nothing once the instructions are already in that language,
     which is where German gets the signal from.

     Anything that is not a plain imperative is best avoided. A field label, a
     fenced block and a "here is a message" framing were all tried, and all
     three sent the model into a runaway generation on some inputs, taking p95
     from under two seconds to about fifty.
     */
    func prompt(for text: String) -> String {
        switch self {
        case .german:
            return "Korrigiere:\n\n\(text)"
        case .english:
            return "Correct this English text, keeping every word:\n\n\(text)"
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

    /**
     Which language this text is in, or nil if it is not one being corrected.

     Detection deliberately ranges over every language the app knows rather than
     only the enabled ones. Constraining it to the enabled set did not make
     Typoless ignore the others, it made it mislabel them: with only English
     added, a German line came back as English and was corrected under English
     rules by an app the user believed was not set up for German. Worse, with a
     single language enabled the recogniser was skipped entirely and everything
     was declared to be that language without being read at all.
     */
    func detect(_ text: String) -> CorrectionLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = CorrectionLanguage.allCases.map(\.nlLanguage)
        recognizer.processString(text)

        guard
            let dominant = recognizer.dominantLanguage,
            let match = CorrectionLanguage.allCases.first(where: { $0.nlLanguage == dominant })
        else {
            /** Nothing recognisable, so treat it as the first language asked for. */
            return enabled.first
        }

        return enabled.contains(match) ? match : nil
    }
}
