import Foundation

/**
 One way of asking a model to correct text.

 The shipping wording lives in `CorrectionLanguage` and is the baseline every
 other variant is measured against. A variant is a whole prompt rather than a
 patch, so nothing is inherited by accident and two runs differ only in the
 thing named here.

 Everything a backend is told is in this type: the system instructions, the user
 turn, and the extra line free-text backends need in place of guided generation.
 A variant that wants to change any of those changes it here and nowhere else.
 */
struct PromptVariant: Sendable {
    let id: String
    let summary: String

    /**
     What the model is told before it sees the text.

     Takes whether the chunk opens the field, because the shipping wording says
     something about the opening word and must not say it about a chunk that is
     not the opening. Variants with no such rule ignore the flag.
     */
    let instructions: @Sendable (CorrectionLanguage, Bool) -> String

    /** The turn that carries the text. */
    let userPrompt: @Sendable (CorrectionLanguage, String) -> String

    /**
     Appended by backends that answer in free text.

     Guided generation gives the reply its shape for free. Without it, an
     instructed model handed a bare sentence tends to answer the sentence rather
     than correct it.
     */
    let freeTextSuffix: String

    /**
     Second attempt after the model declines.

     The on-device model turns down ordinary text now and again, consistently
     for a given wording, so repeating the same request is pointless. Asking in
     English gets an answer often enough to be worth the round trip.
     */
    func retryInstructions(startsText: Bool) -> String { instructions(.english, startsText) }
    func retryPrompt(_ language: CorrectionLanguage, _ text: String) -> String {
        "Correct this \(language.displayName) text, keeping every word:\n\n\(text)"
    }

    static let defaultFreeTextSuffix =
        "\n\nReply with the corrected text only, on a single line, with no explanation and no quotation marks."
}

extension PromptVariant {
    /**
     Every variant the runner knows about.

     Add one here and it is swept automatically. The first entry is what the app
     ships, so a run with no `--variant` still reports the baseline first.
     */
    static let all: [PromptVariant] = [shipping, previous, terse, noOp, protective, examples, terminal, bounded]

    static func named(_ id: String) -> PromptVariant? {
        all.first { $0.id == id }
    }

    /** Exactly what `CorrectionLanguage` says today. */
    static let shipping = PromptVariant(
        id: "shipping",
        summary: "The wording the app ships",
        instructions: { $0.instructions(startsText: $1) },
        userPrompt: { language, text in language.prompt(for: text) },
        freeTextSuffix: defaultFreeTextSuffix
    )

    /** Strips the wording back to the rule and nothing else, to see what the length is buying. */
    static let terse = PromptVariant(
        id: "terse",
        summary: "One sentence, no elaboration",
        instructions: { language, _ in
            switch language {
            case .english:
                return "Fix spelling, punctuation, capitalisation and spacing. Change nothing else."
            case .german:
                return """
                Korrigiere Rechtschreibung (auch fehlende Umlaute), Satzzeichen (auch \
                fehlende Kommas vor Nebensaetzen), Gross- und Kleinschreibung und \
                Abstaende. Aendere sonst nichts.
                """
            /**
             Variants compare wordings for the two languages that have
             datasets. Anything else keeps the shipping instructions, so
             adding a language does not enrol it in an experiment.
             */
            default: return language.instructions(startsText: true)
            }
        },
        userPrompt: { language, text in language.prompt(for: text) },
        freeTextSuffix: defaultFreeTextSuffix
    )

    /**
     An explicit licence to do nothing.

     The failure that ruins this app is a model improving text that needed
     nothing, and the wording it is built on mentions that case only in passing.
     */
    static let noOp = PromptVariant(
        id: "no-op",
        summary: "Earlier wording, with returning the text unchanged made the expected answer",
        instructions: { language, _ in
            switch language {
            case .english:
                return """
                You correct text that someone has already written.

                You fix only these things: spelling mistakes, missing or wrong \
                punctuation, capitalisation, and spacing.

                Most text you are given is already correct. Returning it exactly \
                as it is, character for character, is the right answer and is \
                never a failure. Only change something you can name as one of the \
                four mistakes above.

                You never rephrase, reword, translate, shorten, expand, or improve \
                the writing. You never add or remove a word. You never change the \
                tone or the meaning.
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

                Die meisten Texte sind bereits korrekt. Den Text unveraendert \
                zurueckzugeben, Zeichen fuer Zeichen, ist dann die richtige \
                Antwort und nie ein Fehler. Aendere nur, was du als einen der vier \
                Fehler oben benennen kannst.

                Du formulierst nichts um, uebersetzt nichts, kuerzt nichts und \
                fuegst kein Wort hinzu und entfernst keines. Du aenderst weder Ton \
                noch Bedeutung.
                """
            /**
             Variants compare wordings for the two languages that have
             datasets. Anything else keeps the shipping instructions, so
             adding a language does not enrol it in an experiment.
             */
            default: return language.instructions(startsText: true)
            }
        },
        userPrompt: { language, text in language.prompt(for: text) },
        freeTextSuffix: defaultFreeTextSuffix
    )

    /**
     Names the spans that look wrong and are not, at the bottom of the prompt.

     The list itself turned out to be worth having, which is why `shipping` now
     carries it. Where it sits turned out to matter more: said last, as here, it
     costs the on-device model most of its sentence-initial capitals in German.
     This variant is kept as the control for that.
     */
    static let protective = PromptVariant(
        id: "protective",
        summary: "Earlier wording plus the protection list, said after the rules",
        instructions: { language, _ in
            switch language {
            case .english:
                return previous.instructions(language, true) + """


                Leave these exactly as they are, even when they look wrong: web \
                addresses, email addresses, @handles, #channels, text in \
                backticks, file names, emoji, and product names written in an \
                unusual case.
                """
            case .german:
                return previous.instructions(language, true) + """


                Folgendes bleibt unveraendert, auch wenn es falsch aussieht: \
                Internetadressen, E-Mail-Adressen, @Namen, #Kanaele, Text in \
                Backticks, Dateinamen, Emojis und Produktnamen mit ungewoehnlicher \
                Schreibweise.
                """
            /**
             Variants compare wordings for the two languages that have
             datasets. Anything else keeps the shipping instructions, so
             adding a language does not enrol it in an experiment.
             */
            default: return language.instructions(startsText: true)
            }
        },
        userPrompt: { language, text in language.prompt(for: text) },
        freeTextSuffix: defaultFreeTextSuffix
    )

    /**
     Shows the job instead of describing it, including one text that needs nothing.

     Small models copy a demonstrated shape more reliably than they follow a
     described one, and the no-op example is the half that matters.
     */
    static let examples = PromptVariant(
        id: "examples",
        summary: "Earlier wording plus two worked examples, one of them a no-op",
        instructions: { language, _ in
            switch language {
            case .english:
                return previous.instructions(language, true) + """


                Example. Text: `i think its ready, can you take a look` \
                Answer: `I think it's ready, can you take a look`

                Example. Text: `Thanks for the quick turnaround on that.` \
                Answer: `Thanks for the quick turnaround on that.`
                """
            case .german:
                return previous.instructions(language, true) + """


                Beispiel. Text: `koenntest du das nochmal pruefen bevor wir es abschicken` \
                Antwort: `Könntest du das nochmal prüfen, bevor wir es abschicken`

                Beispiel. Text: `Danke für die schnelle Rückmeldung.` \
                Antwort: `Danke für die schnelle Rückmeldung.`
                """
            /**
             Variants compare wordings for the two languages that have
             datasets. Anything else keeps the shipping instructions, so
             adding a language does not enrol it in an experiment.
             */
            default: return language.instructions(startsText: true)
            }
        },
        userPrompt: { language, text in language.prompt(for: text) },
        freeTextSuffix: defaultFreeTextSuffix
    )

    /**
     One rule about the mark at the end.

     Isolates the single change every backend makes most often: finishing a
     chat message with a full stop that the user did not type. It is punctuation,
     so the guardrail accepts it, and it is not a correction, so the user did not
     ask for it.
     */
    static let terminal = PromptVariant(
        id: "terminal",
        summary: "Earlier wording plus a rule against adding a mark at the end",
        instructions: { language, _ in
            switch language {
            case .english:
                return previous.instructions(language, true) + """


                If the text does not end with a full stop, question mark or \
                exclamation mark, do not add one. A message written without one \
                is not a mistake.
                """
            case .german:
                return previous.instructions(language, true) + """


                Wenn der Text nicht mit Punkt, Fragezeichen oder Ausrufezeichen \
                endet, setze keines. Eine Nachricht ohne Schlusszeichen ist kein \
                Fehler.
                """
            /**
             Variants compare wordings for the two languages that have
             datasets. Anything else keeps the shipping instructions, so
             adding a language does not enrol it in an experiment.
             */
            default: return language.instructions(startsText: true)
            }
        },
        userPrompt: { language, text in language.prompt(for: text) },
        freeTextSuffix: defaultFreeTextSuffix
    )

    /**
     Both extra rules, with the capitalisation rule said again at the end.

     The protection list on its own costs the on-device model most of its
     sentence-initial capitals, because "leave this exactly as it is" reads as
     advice about the whole text rather than about the spans named. Naming only
     mechanical spans and then repeating the rule the list displaced is what
     keeps that from happening.
     */
    static let bounded = PromptVariant(
        id: "bounded",
        summary: "Terminal-mark rule, a narrow protection list, and the capitalisation rule restated",
        instructions: { language, _ in
            switch language {
            case .english:
                return previous.instructions(language, true) + """


                If the text does not end with a full stop, question mark or \
                exclamation mark, do not add one. A message written without one \
                is not a mistake.

                Copy web addresses, email addresses, @handles, #channels, text \
                in backticks and emoji across character for character.

                The first word of every sentence still starts with a capital letter.
                """
            case .german:
                return previous.instructions(language, true) + """


                Wenn der Text nicht mit Punkt, Fragezeichen oder Ausrufezeichen \
                endet, setze keines. Eine Nachricht ohne Schlusszeichen ist kein \
                Fehler.

                Internetadressen, E-Mail-Adressen, @Namen, #Kanaele, Text in \
                Backticks und Emojis uebernimmst du Zeichen fuer Zeichen.

                Jeder Satz beginnt trotzdem mit einem Grossbuchstaben, und jedes \
                Substantiv wird grossgeschrieben.
                """
            /**
             Variants compare wordings for the two languages that have
             datasets. Anything else keeps the shipping instructions, so
             adding a language does not enrol it in an experiment.
             */
            default: return language.instructions(startsText: true)
            }
        },
        userPrompt: { language, text in language.prompt(for: text) },
        freeTextSuffix: defaultFreeTextSuffix
    )

    /**
     The wording that shipped before the eval existed.

     Kept literal rather than derived, so the improvement stays measurable after
     `CorrectionLanguage` has moved on. `shipping` against `previous` is the
     before and after of one change: the same exception about protected spans,
     moved from nowhere to the top. Said at the bottom instead, it costs the
     on-device model most of its sentence-initial capitals in German, which is
     what `protective` measures.
     */
    static let previous = PromptVariant(
        id: "previous",
        summary: "The instructions as they were before the eval",
        instructions: { language, _ in
            switch language {
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
            /**
             Variants compare wordings for the two languages that have
             datasets. Anything else keeps the shipping instructions, so
             adding a language does not enrol it in an experiment.
             */
            default: return language.instructions(startsText: true)
            }
        },
        userPrompt: { language, text in language.prompt(for: text) },
        freeTextSuffix: defaultFreeTextSuffix
    )
}

extension PromptVariant {
    /**
     A candidate wording read from a file.

     Sweeping wordings by editing this file and rebuilding is fine for the
     handful kept here permanently, and hopeless for the dozen or so thrown at
     the model in an afternoon of tuning. A definition carries exactly what a
     variant needs and nothing else, so candidates can be generated, scored and
     discarded without touching Swift at all.
     */
    struct Definition: Decodable, Sendable {
        let id: String
        var rationale: String?
        let enInstructions: String
        let deInstructions: String
        let enUserPrompt: String
        let deUserPrompt: String

        /**
         Appended only for the chunk that opens the field.

         Without this a loaded candidate carried its opening-capital rule into
         every chunk while the shipping wording dropped it after the first, so
         the two were not being asked the same thing on any message with more
         than one line. Omit both to say nothing about openings at all.
         */
        var enOpening: String?
        var deOpening: String?
    }

    /** Where the user's text is spliced into a loaded user turn. */
    static let textPlaceholder = "{TEXT}"

    static func loaded(from url: URL) throws -> [PromptVariant] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let definitions = try decoder.decode([Definition].self, from: Data(contentsOf: url))

        for definition in definitions {
            guard
                definition.enUserPrompt.contains(textPlaceholder),
                definition.deUserPrompt.contains(textPlaceholder)
            else {
                throw EvalError.unknownArgument(
                    "\(definition.id): both user prompts must contain \(textPlaceholder)"
                )
            }
        }

        return definitions.map { definition in
            PromptVariant(
                id: definition.id,
                summary: definition.rationale ?? "loaded from a file",
                instructions: { language, startsText in
                    let german = language == .german
                    let body = german ? definition.deInstructions : definition.enInstructions
                    let opening = german ? definition.deOpening : definition.enOpening

                    return startsText ? body + (opening ?? "") : body
                },
                userPrompt: { language, text in
                    let template = language == .german ? definition.deUserPrompt : definition.enUserPrompt
                    return template.replacingOccurrences(of: textPlaceholder, with: text)
                },
                freeTextSuffix: defaultFreeTextSuffix
            )
        }
    }
}
