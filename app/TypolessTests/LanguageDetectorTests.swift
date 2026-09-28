import Testing
@testable import Typoless

/**
 Short text is where language detection fails, and short text is most of what
 people write.

 The recogniser judges a language by its letters, and a typo takes some of them
 away, so the app is least sure of itself exactly where it is needed. "chekc
 this todo" reads as Portuguese at 0.36 against English at 0.30, and a chunk in
 a language the user has not added is dropped without a word: the correction
 that never happened looks the same as an app that is not running.

 What has to keep working is the reason the check exists at all. A German line
 in an English-only setup is still left alone, because there the recogniser is
 certain and being certain is the whole test.
 */
struct LanguageDetectorTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        let enabled: Array<CorrectionLanguage>
        let expected: CorrectionLanguage?

        var testDescription: String { name }
    }

    static let cases: Array<Case> = [
        Case(
            name: "a short line with a typo in it",
            text: "chekc this todo",
            enabled: [.english, .german],
            expected: .english
        ),
        Case(
            name: "the same line spelled correctly",
            text: "check this todo",
            enabled: [.english, .german],
            expected: .english
        ),
        Case(
            name: "two words",
            text: "teh meeting",
            enabled: [.english, .german],
            expected: .english
        ),
        Case(
            name: "a confident German line where German is not corrected",
            text: "Ich habe das Thema gestern mit dem Team besprochen und wir sind uns einig.",
            enabled: [.english],
            expected: nil
        ),
        Case(
            name: "a confident English line where English is not corrected",
            text: "I have looked at the report and the numbers in the last column are wrong.",
            enabled: [.german],
            expected: nil
        ),
        Case(
            name: "a German line where German is corrected",
            text: "Ich gehe heut nach hause",
            enabled: [.english, .german],
            expected: .german
        ),
        Case(
            name: "nothing to read",
            text: "   ",
            enabled: [.german, .english],
            expected: .german
        ),
    ]

    @Test(arguments: cases)
    func `the language is the likeliest one the user corrects`(_ row: Case) {
        // Arrange
        let detector = LanguageDetector(enabled: row.enabled)

        // Act
        let result = detector.detect(row.text)

        // Assert
        #expect(result == row.expected)
    }
}
