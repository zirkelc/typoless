import Foundation

/**
 One thing the app is expected to do to one piece of text.

 `expected` is the whole corrected text rather than a list of edits, because
 that is what the pipeline produces and what the user sees. The errors a case
 contains are derived by diffing `input` against `expected`, so a case never has
 to state them twice and they can never fall out of step.

 A case where `expected` equals `input` is a negative: text that is already
 right and must come back untouched.
 */
struct EvalCase: Decodable, Sendable {
    let id: String
    let input: String
    let expected: String
    /**
     Other answers that are just as right, where the language allows more than
     one. "wegen dem Termin" is accepted German and "wegen des Termins" is the
     written standard, and a model that picks either has not made a mistake.
     */
    var alternatives: [String]? = nil
    let tags: [String]

    var isNegative: Bool { expected == input }

    /** The expected answer first, then the alternatives. */
    var acceptedAnswers: [String] { [expected] + (alternatives ?? []) }
}

/** A language's worth of cases, one file per language. */
struct Dataset: Decodable, Sendable {
    /** Says out loud what counts as an error here, since several calls are judgement rather than grammar. */
    let policy: String
    let cases: [EvalCase]
}

enum DatasetLoader {
    /**
     Finds the dataset for a language by its two-letter code.

     Nothing here knows the name of any language: the code comes from
     `CorrectionLanguage`, so a new language needs a new enum case and a new
     file and nothing else.
     */
    static func load(_ language: CorrectionLanguage, from directory: URL) throws -> Dataset {
        let url = directory.appendingPathComponent("\(language.nlLanguage.rawValue).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Dataset.self, from: data)
    }

    /** Walks up from the executable until it finds the datasets, so the tool runs from anywhere. */
    static func locateDirectory(startingAt start: URL) -> URL? {
        var directory = start

        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("Datasets")
            var isDirectory: ObjCBool = false

            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate
            }

            directory = directory.deletingLastPathComponent()
        }

        return nil
    }
}
