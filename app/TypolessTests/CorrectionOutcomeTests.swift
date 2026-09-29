import Testing
@testable import Typoless

/**
 A pass has to be able to say what it did, including when it did nothing.

 Every refusal used to be a log line, which means it was visible to whoever
 thought to watch the log and to nobody else. The user saw an app that had done
 nothing, and an app that has done nothing looks exactly like an app that is not
 running. These are the reasons a history entry and a bug report now carry.
 */
struct CorrectionOutcomeTests {
    /** Answers with the text it was given, so only the pipeline is under test. */
    private static func pass(
        over text: String,
        enabled: Array<CorrectionLanguage>,
        answer: @escaping @Sendable (String) -> String?
    ) async throws -> ChunkedCorrection.Pass {
        try await ChunkedCorrection.run(
            over: text,
            settings: .permissive,
            detector: LanguageDetector(enabled: enabled),
            appliesGuardrail: true,
            deadline: nil
        ) { source, _, _ in answer(source) }
    }

    @Test
    func `text in a language that is not corrected says which language it was`() async throws {
        // Arrange
        let text = "I have looked at the report and the numbers in the last column are wrong."

        // Act
        let pass = try await Self.pass(over: text, enabled: [.german]) { _ in
            Issue.record("The model was asked about text it should never have seen")
            return nil
        }

        // Assert
        #expect(pass.edits.isEmpty)
        #expect(pass.outcome.languages.isEmpty)
        #expect(pass.outcome.notes.count == 1)
        #expect(pass.outcome.notes.first?.refusal == .languageNotCorrected(.english))
        #expect(pass.outcome.notes.first?.isApplied == false)
    }

    @Test
    func `a change that is made is recorded as applied, with the language`() async throws {
        // Arrange
        let text = "teh meeting is at noon"

        // Act
        let pass = try await Self.pass(over: text, enabled: [.english, .german]) { _ in
            "the meeting is at noon"
        }

        // Assert
        #expect(pass.edits.count == 1)
        #expect(pass.outcome.languages == [.english])
        #expect(pass.outcome.appliedCount == 1)

        let note = try #require(pass.outcome.notes.first)
        #expect(note.before == "teh")
        #expect(note.after == "the")
        #expect(note.isApplied)
        #expect(note.refusal == nil)
    }

    @Test
    func `a change the rules forbid is recorded with the reason`() async throws {
        // Arrange, a settings object that allows everything but spelling
        let text = "teh meeting is at noon"
        let rules = CorrectionRule.allCases.filter { $0 != .typos }
        let settings = AppSettings(languages: [
            .english: LanguageSettings(isEnabled: true, model: nil, allowedRules: Set(rules)),
        ])

        // Act
        let pass = try await ChunkedCorrection.run(
            over: text,
            settings: settings,
            detector: LanguageDetector(enabled: [.english]),
            appliesGuardrail: true,
            deadline: nil
        ) { _, _, _ in "the meeting is at noon" }

        // Assert
        #expect(pass.edits.isEmpty)
        #expect(pass.outcome.notes.count == 1)
        #expect(pass.outcome.notes.first?.refusal == .ruleTurnedOff)
    }

    /**
     The message that started this: German throughout, signed with a name.

     "Christian Cook" reads as English at 0.29, where a guess among seven
     languages is worth 0.14, and the pass reported German and English. Worse
     than the label, that line would have been corrected under English rules in
     the middle of a German message.
     */
    @Test
    func `a line too short to have a language follows the message it is in`() async throws {
        // Arrange
        let email = """
        Hallo Frau Gottschalk

        anbei die Vollstaendigkeitserklaerung.

        Vielen Dank und beste Gruesse
        Christian Cook
        """

        // Act
        let pass = try await Self.pass(over: email, enabled: [.english, .german]) { _ in nil }

        // Assert
        #expect(pass.outcome.languages == [.german])
    }

    /** A real change of language is still a change of language, not a short line. */
    @Test
    func `a confident sentence keeps its own language inside another`() async throws {
        // Arrange
        let mixed = """
        Hallo Frau Gottschalk

        I have attached the report you asked for, and the numbers are in the last column.

        Vielen Dank und beste Gruesse
        """

        // Act
        let pass = try await Self.pass(over: mixed, enabled: [.english, .german]) { _ in nil }

        // Assert
        #expect(Set(pass.outcome.languages) == [.german, .english])
    }

    @Test
    func `a reply in capitals is refused and says so`() async throws {
        // Arrange
        let text = "the meeting is at noon and the room is booked"

        // Act
        let pass = try await Self.pass(over: text, enabled: [.english]) { source in
            source.uppercased()
        }

        // Assert
        #expect(pass.edits.isEmpty)
        #expect(pass.outcome.notes.first?.refusal == .shouting)
    }
}
