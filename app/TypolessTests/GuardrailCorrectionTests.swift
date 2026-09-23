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
         A space typed one letter late.

         Word by word it reads as "shouldw" losing a letter and "e" becoming
         "we", and the second looks like a new word. Joined, the two are the
         same letters with the space in another place, which is spacing.
         */
        GuardrailCase("a space typed one letter late", "Very nice, shouldw e add", "Very nice, should we add", expect: "Very nice, should we add"),
        GuardrailCase("a space typed one letter early", "can w eadd it", "can we add it", expect: "can we add it"),
        /** Moving a space is spacing, so it needs the spacing rule like any other. */
        GuardrailCase(
            "a moved space is refused where spacing is not allowed",
            "shouldw e add",
            "should we add",
            allowing: [.typos, .commas],
            expect: "shouldw e add"
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
/**
 A model that carries on past the end of the text.

 Apple's model does this to a message that stops mid-sentence: it reads the
 instructions the framework appends after the prompt as more of the text, and
 writes them into its answer. The words after the end are never a correction,
 so they are cut off before the rest is judged, and the fixes before them still
 land. The cut counts as one refusal, since the model did stray.
 */
struct ContinuationTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase(
            "words added after the end are cut off",
            "Very nice, shouldw e add",
            "Very nice, should we add a response format in json.",
            expect: "Very nice, should we add"
        ),
        GuardrailCase(
            "a fixed last word keeps its fix and loses what follows it",
            "thanks, and one more thing about teh",
            "Thanks, and one more thing about the response",
            expect: "Thanks, and one more thing about the"
        ),
        GuardrailCase(
            "a word split in two at the end is not a continuation",
            "see you soon tim,i",
            "See you soon Tim, I",
            expect: "See you soon Tim, I"
        ),
        GuardrailCase("a full stop at the end is not a continuation", "hello world", "Hello world.", expect: "Hello world."),
        /** Cut or not, a model that answered the text has still rewritten it. */
        GuardrailCase(
            "an answer is still refused whole",
            "what is the capital of france",
            "The capital of France is Paris.",
            expect: "what is the capital of france"
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

/** Grammar is a rule of its own, asked separately from typos. */
struct GrammarTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase(
            "a word form lands where grammar is allowed",
            "danke, und wegen dem termin am",
            "Danke, und wegen des Termins am",
            in: .german,
            expect: "Danke, und wegen des Termins am"
        ),
        GuardrailCase(
            "and stays as written where it is not",
            "danke, und wegen dem termin am",
            "Danke, und wegen des Termins am",
            allowing: Set(CorrectionRule.allCases).subtracting([.grammar]),
            in: .german,
            expect: "Danke, und wegen dem termin am"
        ),
        /** Turning grammar off must not take typos with it, nor the other way round. */
        GuardrailCase(
            "a typo still lands with grammar off",
            "teh cat sat",
            "the cat sat",
            allowing: Set(CorrectionRule.allCases).subtracting([.grammar]),
            in: .english,
            expect: "the cat sat"
        ),
        GuardrailCase(
            "a verb form lands with typos off",
            "she go home",
            "she goes home",
            allowing: Set(CorrectionRule.allCases).subtracting([.typos]),
            in: .english,
            expect: "she goes home"
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

/**
 A reply in capitals is not a capitalisation fix.

 Each word on its own reads as the same letters in another case, so every one
 of them passed, and a whole message came back shouted. Whether that happened
 is only visible across the line: a real fix puts a word or two into capitals,
 a shouting model puts nearly all of them.
 */
struct ShoutingTests {
    static let cases: Array<GuardrailCase> = [
        GuardrailCase(
            "a message returned in capitals is left as written",
            "we should sue the ectual enums here, not inlined strings",
            "WE SHOULD SUE THE EXACT ENUMES HERE, NOT INLINED STRINGS",
            in: .english,
            expect: "we should sue the ectual enums here, not inlined strings"
        ),
        GuardrailCase(
            "acronyms still get their capitals",
            "the api returns json and html",
            "The API returns JSON and HTML",
            in: .english,
            expect: "The API returns JSON and HTML"
        ),
        /** Most words in capitals, but not all: acronyms, which is what real fixes look like. */
        GuardrailCase(
            "a line of acronyms is not shouting",
            "api, sdk and cli docs are updated",
            "API, SDK and CLI docs are updated",
            in: .english,
            expect: "API, SDK and CLI docs are updated"
        ),
        /** Code stays as written, so it cannot count against a reply that shouts everything else. */
        GuardrailCase(
            "shouting around code is still shouting",
            "run `pnpm install` before you build",
            "RUN `pnpm install` BEFORE YOU BUILD",
            in: .english,
            expect: "run `pnpm install` before you build"
        ),
        GuardrailCase("two words are enough to shout", "ok thanks", "OK THANKS", in: .english, expect: "ok thanks"),
        GuardrailCase("one word in capitals is an acronym", "asap", "ASAP", in: .english, expect: "ASAP"),
        GuardrailCase(
            "text written in capitals may stay in capitals",
            "PLEASE CALL ME BACK ASAP",
            "PLEASE CALL ME BACK ASAP.",
            in: .english,
            expect: "PLEASE CALL ME BACK ASAP."
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
