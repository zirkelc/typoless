import Testing
@testable import Typoless

/** Corrections the guardrail lets through, applied as the model returned them. */
struct CorrectionsAppliedTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase("casing + apostrophe", "i think its ready", "I think it's ready", expect: "I think it's ready"),
        GuardrailCase("double space", "hello  world", "hello world", expect: "hello world"),
        GuardrailCase("space before comma", "hello , world", "hello, world", expect: "hello, world"),
        GuardrailCase("missing period + caps", "hello world", "Hello world.", expect: "Hello world."),
        GuardrailCase("typo", "teh cat sat", "the cat sat", expect: "the cat sat"),
        GuardrailCase("your/you're", "i hope your well", "I hope you're well", expect: "I hope you're well"),
        GuardrailCase("german caps", "wir gehen ins kino", "Wir gehen ins Kino", expect: "Wir gehen ins Kino"),
        GuardrailCase("german sharp s", "das war grosse klasse", "Das war große Klasse.", expect: "Das war große Klasse."),
        GuardrailCase(
            "missing comma",
            "if you can come let me know",
            "If you can come, let me know",
            expect: "If you can come, let me know"
        ),
        GuardrailCase("umlaut restored", "wir treffen uns im buero", "Wir treffen uns im Büro", expect: "Wir treffen uns im Büro"),
        GuardrailCase(
            "umlaut plus comma",
            "koenntest du das pruefen bevor wir abschicken",
            "Könntest du das prüfen, bevor wir abschicken",
            expect: "Könntest du das prüfen, bevor wir abschicken"
        ),
        GuardrailCase("eszett restored", "das war eine grosse hilfe", "Das war eine große Hilfe", expect: "Das war eine große Hilfe"),
        GuardrailCase(
            "word split by punctuation",
            "hi tim,i hope your  well",
            "Hi Tim, I hope you're well.",
            expect: "Hi Tim, I hope you're well."
        ),
        GuardrailCase(
            "transposed letters plus a capital",
            "the meeting is on wendesday at three",
            "The meeting is on Wednesday at three",
            expect: "The meeting is on Wednesday at three"
        ),
        /**
         A space is not an anchor.

         Every run of whitespace is the same single space, so a longest common
         subsequence over atoms is free to match any space to any other one, and it
         prefers doing so: matching spaces is cheap and there are many of them. The
         alignment then slips by one word and the diff reports that the user's
         "mistake" should become "my", which the guardrail refuses, correctly, taking
         the real corrections down with it. Only words anchor the alignment now.
         */
        GuardrailCase(
            "punctuation and spacing fixed in one sentence",
            "sorry ,my mistake . i will redo it .",
            "Sorry, my mistake. I will redo it.",
            expect: "Sorry, my mistake. I will redo it."
        ),
        GuardrailCase(
            "several spaces before commas",
            "thanks , and yes , that works",
            "Thanks, and yes, that works",
            expect: "Thanks, and yes, that works"
        ),
        /**
         A doubled word is still a word, and removing one is still a deletion, so the
         alignment has to survive the repetition without the guardrail's answer
         changing. It refuses, as it refuses every deletion. That is deliberate: the
         same shape covers "the the" and a word the user meant to repeat.
         */
        GuardrailCase(
            "a doubled word is not removed, even where the words around it repeat",
            "the the same the same day",
            "The same the same day",
            expect: "the the same the same day"
        ),
    ]

    @Test(arguments: cases)
    func `the field ends up as expected`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/** A rewrite is refused, and the user's wording is kept. */
struct RewritingRefusedTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase("word inserted", "hello world", "hello beautiful world", expect: "hello world"),
        GuardrailCase("word deleted", "i am very tired", "I am tired", expect: "I am very tired"),
        GuardrailCase("synonym swap", "that is good", "That is excellent", expect: "That is good"),
        GuardrailCase("meaning change", "the meeting is at 5", "The meeting was at 5", expect: "The meeting is at 5"),
        GuardrailCase(
            "umlaut fold is not a licence",
            "wir fahren nach hause",
            "Wir fahren nach Häuserblock",
            expect: "Wir fahren nach hause"
        ),
        /** Ignoring case in the spelling distance must not turn a word swap into a typo. */
        GuardrailCase(
            "pronoun swap",
            "Passt dir Dienstag um 10 Uhr?",
            "Passt ihr Dienstag um 10 Uhr?",
            expect: "Passt dir Dienstag um 10 Uhr?"
        ),
        GuardrailCase(
            "word lengthened",
            "The deploy finished at 14:32",
            "The deployment finished at 14:32",
            expect: "The deploy finished at 14:32"
        ),
        GuardrailCase("different word, same first letter", "sie ist schon hier", "sie hat schon hier", expect: "sie ist schon hier"),
    ]

    @Test(arguments: cases)
    func `the wording is preserved`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}

/** Known gaps, pinned so they cannot change unnoticed. */
struct KnownGapTests {
    /**
     A word whose ending changes within two edits reads as a typo to the distance
     rule, so "hause" becomes "häuser" and the sentence now says something else.
     This was never blocked on its merits: before the spelling distance ignored
     case, the same change was refused when a model capitalised it and accepted
     when it did not. Closing it needs a rule about word endings, not a budget.
     */
    @Test func `word ending changed within budget`() {
        // Arrange
        let original = "wir fahren nach hause"
        let output = "wir fahren nach häuser"

        // Act
        let result = Guardrail.corrected(original, output)

        // Assert
        #expect(result == "wir fahren nach häuser")
    }

    /**
     A rewrite of one phrase, alongside a capital that is genuinely a correction.

     The capital lands and the rewrite does not, which is what the rewriting cases
     ask for in the same situation. It used to be refused outright, and the only
     thing that made this case different was that the alignment happened to split
     the rewritten phrase into two changes rather than one, so it crossed the trust
     threshold by an accident of where the words lined up. Whether a pass is
     trusted should not turn on that.
     */
    @Test func `one phrase rewritten, the capital still lands`() {
        // Arrange
        let original = "the meeting is at 5"
        let output = "The meeting has been scheduled for 5"

        // Act
        let result = Guardrail.corrected(original, output)

        // Assert
        #expect(result == "The meeting is at 5")
    }
}

/** A reply that is not a correction of the text at all is refused whole. */
struct WholeChunkRefusedTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase("translation", "wir gehen ins kino", "we are going to the cinema", expect: "wir gehen ins kino"),
        GuardrailCase(
            "mostly rewritten",
            "can you send it over when your done",
            "Please forward it once you have finished.",
            expect: "can you send it over when your done"
        ),
        GuardrailCase(
            "model answered instead",
            "what is the capital of france",
            "The capital of France is Paris.",
            expect: "what is the capital of france"
        ),
    ]

    @Test(arguments: cases)
    func `the text is left as written`(_ row: GuardrailCase) {
        // Arrange
        let expected = row.expected

        // Act
        let result = Guardrail.corrected(row)

        // Assert
        #expect(result == expected)
    }
}
