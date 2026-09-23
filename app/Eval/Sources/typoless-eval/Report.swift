import Foundation

/** Prints the run and writes it somewhere it can be compared against later. */
enum Report {
    struct Run: Codable, Sendable {
        let startedAt: Date
        let summaries: [Summary]
        let results: [String: [Scoring.CaseResult]]
    }

    /**
     One row per configuration.

     False positives get two columns because the totals hide the shape: one case
     mangled six ways and six cases nudged once each are the same number and not
     the same problem.
     */
    static func table(_ summaries: [Summary]) -> String {
        let header = [
            "model", "lang", "variant", "grd",
            "exact", "recall", "fp", "fp/case", "clean",
            "med s", "p95 s", "drop", "rej", "off", "mix",
        ]

        var rows = [header]

        for summary in summaries {
            rows.append([
                summary.model,
                summary.language,
                summary.variant,
                summary.guardrail ? "on" : "off",
                percent(summary.exactMatchRate),
                percent(summary.fixRecall),
                "\(summary.casesWithFalsePositive)/\(summary.falsePositiveTotal)",
                String(format: "%.2f", summary.falsePositivesPerCase),
                "\(summary.negativesUntouched)/\(summary.negatives)",
                String(format: "%.2f", summary.medianSeconds),
                String(format: "%.2f", summary.p95Seconds),
                "\(summary.chunksDropped)",
                "\(summary.editsRejected)",
                "\(summary.offRuleEdits)",
                "\(summary.mixedOffRuleEdits)",
            ])
        }

        let widths = (0..<header.count).map { column in
            rows.map { $0[column].count }.max() ?? 0
        }

        return rows.enumerated().map { index, row in
            let line = zip(row, widths)
                .map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }
                .joined(separator: "  ")

            guard index == 0 else { return line }
            return line + "\n" + String(repeating: "-", count: line.count)
        }
        .joined(separator: "\n")
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    /** The cases worth reading, which are the ones that did not come back right. */
    static func failures(_ results: [Scoring.CaseResult]) -> String {
        results.filter { !$0.exactMatch }.map { result in
            """
            \(result.id) [\(result.tags.joined(separator: " "))] \
            required \(result.fixed)/\(result.required), \(result.falsePositives) unrequested
                 in: \(escaped(result.input))
                exp: \(escaped(result.expected))
                got: \(escaped(result.output))
            """
        }
        .joined(separator: "\n")
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "\\n")
    }

    static func write(_ run: Run, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(run).write(to: url)
    }
}
