import Foundation
import Testing
@testable import Typoless

/**
 One row of a guardrail table: the text the user wrote, the text the model
 returned, the rules the language permits, and what the field should end up
 containing.
 */
struct GuardrailCase: Sendable, CustomTestStringConvertible {
    let name: String
    let original: String
    let output: String
    let rules: Set<CorrectionRule>
    /** Which dictionary to judge word forms by, or nil to judge every changed word as a typo. */
    let language: CorrectionLanguage?
    let expected: String

    init(
        _ name: String,
        _ original: String,
        _ output: String,
        allowing rules: Set<CorrectionRule> = Set(CorrectionRule.allCases),
        in language: CorrectionLanguage? = nil,
        expect expected: String
    ) {
        self.name = name
        self.original = original
        self.output = output
        self.rules = rules
        self.language = language
        self.expected = expected
    }

    var testDescription: String { name }
}

/**
 One row of a classification table: an edit, and every question it raises.

 An empty set means the edit is not a correction at all.
 */
struct RuleCase: Sendable, CustomTestStringConvertible {
    let name: String
    let original: String
    let corrected: String
    let language: CorrectionLanguage?
    let expected: Set<CorrectionRule>

    init(
        _ name: String,
        _ original: String,
        _ corrected: String,
        in language: CorrectionLanguage? = nil,
        expect expected: Set<CorrectionRule>
    ) {
        self.name = name
        self.original = original
        self.corrected = corrected
        self.language = language
        self.expected = expected
    }

    var testDescription: String { name }
}

enum Guardrail {
    /**
     Runs the text the user wrote and the text the model returned through the
     guardrail, and returns what the field would end up containing.
     */
    static func corrected(
        _ original: String,
        _ modelOutput: String,
        allowing rules: Set<CorrectionRule> = Set(CorrectionRule.allCases),
        in language: CorrectionLanguage? = nil
    ) -> String {
        let protected = ProtectedSpans.find(in: original)
        let verdict = EditGuardrail.filter(
            TextDiff.edits(from: original, to: modelOutput),
            in: original,
            allowing: rules,
            protectedBy: protected,
            language: language
        )

        return verdict.isTrustworthy ? TextDiff.apply(verdict.accepted, to: original) : original
    }

    /** Runs a guardrail row, so every table asserts the same way. */
    static func corrected(_ row: GuardrailCase) -> String {
        corrected(row.original, row.output, allowing: row.rules, in: row.language)
    }

    /**
     Every question a single edit raises, and every one of them has to be
     permitted before it is applied.

     Anything but exactly one edit reports no rules, so a case that splits into
     several edits cannot pass by accident.
     */
    static func rules(
        _ original: String,
        _ corrected: String,
        in language: CorrectionLanguage? = nil
    ) -> Set<CorrectionRule> {
        let edits = TextDiff.edits(from: original, to: corrected)
        let kinds = edits.map { EditGuardrail.classify($0, in: original, language: language) }

        return kinds.count == 1 ? (kinds[0] ?? []) : []
    }
}
