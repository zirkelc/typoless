import Foundation

/**
 Judges one output against what the case asked for.

 Everything is derived by diffing with `TextDiff`, the same comparison the app
 uses to decide what to apply, so a metric can never claim a change the app
 would not have made.

 The idea is simple. Diff the input against the expected text and you have the
 errors the case contains. Diff the expected text against the output and you
 have every way the model got it wrong. Each of those defects sits either on top
 of an error the case asked about, in which case that error was missed or fixed
 the wrong way, or somewhere else entirely, in which case the model changed
 something nobody asked it to.

 Attributing defects by position rather than matching edit lists head to head
 matters because `TextDiff` merges a change with an adjacent insertion. Two
 corrections that differ only in how they were grouped would otherwise both
 count as wrong.
 */
enum Scoring {
    struct CaseResult: Codable, Sendable {
        let id: String
        let tags: [String]
        let isNegative: Bool
        let input: String
        let expected: String
        let output: String

        /** Errors the case contains, derived from input against expected. */
        let required: Int
        /** Errors the model got right. */
        let fixed: Int
        /** Changes the model made that the case did not ask for. */
        let falsePositives: Int

        let exactMatch: Bool
        /** Whether the output is byte-identical to the input, which is the win condition for a negative. */
        let untouched: Bool

        let seconds: Double
        let chunksDropped: Int
        let editsRejected: Int
        let modelDeclined: Int
        /** Chunks asked about twice because the markers did not survive. */
        let maskRetries: Int
        /** Changes the model proposed that touch a rule the user switched off. */
        var offRuleEdits = 0
        /** Of those, the ones that also carry a rule the user still wants. */
        var mixedOffRuleEdits = 0
    }

    static func score(
        _ testCase: EvalCase,
        output: EvalPipeline.Outcome,
        seconds: Double
    ) -> CaseResult {
        /** Scored against the alternative the output chose, where it chose one. */
        let reference = testCase.acceptedAnswers.first { $0 == output.text } ?? testCase.expected
        let required = TextDiff.edits(from: testCase.input, to: reference)
        let defects = TextDiff.edits(from: reference, to: output.text)

        /** Where each required correction ended up in the expected text. */
        let targets = images(of: required, in: testCase.input)

        var missed = Set<Int>()
        var falsePositives = 0

        for defect in defects {
            let span = offsets(of: defect.range, in: reference)
            let hits = targets.indices.filter { targets[$0].overlaps(span) }

            if hits.isEmpty {
                falsePositives += 1
            } else {
                missed.formUnion(hits)
            }
        }

        return CaseResult(
            id: testCase.id,
            tags: testCase.tags,
            isNegative: testCase.isNegative,
            input: testCase.input,
            expected: testCase.expected,
            output: output.text,
            required: required.count,
            fixed: required.count - missed.count,
            falsePositives: falsePositives,
            exactMatch: testCase.acceptedAnswers.contains(output.text),
            untouched: output.text == testCase.input,
            seconds: seconds,
            chunksDropped: output.chunksDropped,
            editsRejected: output.editsRejected,
            modelDeclined: output.modelDeclined,
            maskRetries: output.maskRetries,
            offRuleEdits: output.offRuleEdits,
            mixedOffRuleEdits: output.mixedOffRuleEdits
        )
    }

    /**
     Character spans in the corrected text that each required edit is responsible for.

     Edits arrive in order and do not overlap, so the shift each one causes
     applies to every edit after it.
     */
    private static func images(of edits: [TextEdit], in input: String) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var shift = 0

        for edit in edits {
            let start = input.distance(from: input.startIndex, to: edit.range.lowerBound) + shift
            let length = edit.replacement.count

            /** A pure deletion has no width, so widen it or nothing can ever land on it. */
            spans.append(length == 0 ? (start - 1)..<(start + 1) : start..<(start + length))
            shift += length - edit.original.count
        }

        return spans
    }

    private static func offsets(of range: Range<String.Index>, in text: String) -> Range<Int> {
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let end = text.distance(from: text.startIndex, to: range.upperBound)

        /** An insertion is a point, and a point overlaps nothing, so give it a width. */
        return start == end ? (start - 1)..<(start + 1) : start..<end
    }
}

/** Everything a run of one dataset through one configuration adds up to. */
struct Summary: Codable, Sendable {
    let model: String
    let language: String
    let variant: String
    let guardrail: Bool

    let cases: Int
    let exactMatches: Int
    let requiredTotal: Int
    let fixedTotal: Int
    let falsePositiveTotal: Int
    /** Cases carrying at least one unrequested change, which is what a user would notice. */
    let casesWithFalsePositive: Int

    let negatives: Int
    let negativesUntouched: Int

    let medianSeconds: Double
    let p95Seconds: Double

    let chunksDropped: Int
    let editsRejected: Int
    let modelDeclined: Int
    /** Chunks asked about twice because the markers did not survive the first reply. */
    let maskRetries: Int
    /** Changes proposed that touch a rule the user switched off, over the whole dataset. */
    let offRuleEdits: Int
    /** Of those, the ones that also carry a rule the user still wants. */
    let mixedOffRuleEdits: Int

    var exactMatchRate: Double { cases == 0 ? 0 : Double(exactMatches) / Double(cases) }
    var fixRecall: Double { requiredTotal == 0 ? 0 : Double(fixedTotal) / Double(requiredTotal) }
    var untouchedCorrectRate: Double { negatives == 0 ? 0 : Double(negativesUntouched) / Double(negatives) }
    var falsePositivesPerCase: Double { cases == 0 ? 0 : Double(falsePositiveTotal) / Double(cases) }

    init(
        model: String,
        language: String,
        variant: String,
        guardrail: Bool,
        results: [Scoring.CaseResult]
    ) {
        self.model = model
        self.language = language
        self.variant = variant
        self.guardrail = guardrail

        cases = results.count
        exactMatches = results.count(where: \.exactMatch)
        requiredTotal = results.reduce(0) { $0 + $1.required }
        fixedTotal = results.reduce(0) { $0 + $1.fixed }
        falsePositiveTotal = results.reduce(0) { $0 + $1.falsePositives }
        casesWithFalsePositive = results.count { $0.falsePositives > 0 }

        let negativeResults = results.filter(\.isNegative)
        negatives = negativeResults.count
        negativesUntouched = negativeResults.count(where: \.untouched)

        let times = results.map(\.seconds).sorted()
        medianSeconds = times.percentile(0.5)
        p95Seconds = times.percentile(0.95)

        chunksDropped = results.reduce(0) { $0 + $1.chunksDropped }
        editsRejected = results.reduce(0) { $0 + $1.editsRejected }
        modelDeclined = results.reduce(0) { $0 + $1.modelDeclined }
        maskRetries = results.reduce(0) { $0 + $1.maskRetries }
        offRuleEdits = results.reduce(0) { $0 + $1.offRuleEdits }
        mixedOffRuleEdits = results.reduce(0) { $0 + $1.mixedOffRuleEdits }
    }
}

private extension Array where Element == Double {
    /** Nearest-rank, which needs no interpolation and never invents a time nobody saw. */
    func percentile(_ fraction: Double) -> Double {
        guard !isEmpty else { return 0 }
        let rank = Int((fraction * Double(count)).rounded(.up))
        return self[Swift.max(0, Swift.min(count - 1, rank - 1))]
    }
}
