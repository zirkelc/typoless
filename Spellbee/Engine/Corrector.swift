import Foundation

/**
 Turns text into corrected text.

 The seam that keeps the on-device model from spreading through the app: the
 engine, the accessibility layer and the UI never learn which backend is behind
 this, which is what lets a different one be swapped in and a fake one be used
 in tests.
 */
protocol Corrector: Sendable {
    func correct(_ text: String) async throws -> String
}

/**
 Fixes only spacing, and only where it is unambiguous.

 Stands in until the model backend lands. Deliberately the most boring member of
 the four edit kinds the app is allowed to make: it needs no model, cannot
 change a word, and still proves the whole path from trigger to written-back
 text.
 */
struct WhitespaceCorrector: Corrector {
    func correct(_ text: String) async throws -> String {
        var lines = text.components(separatedBy: .newlines)

        lines = lines.map { line in
            var collapsed = line
            while collapsed.contains("  ") {
                collapsed = collapsed.replacingOccurrences(of: "  ", with: " ")
            }
            /** Space before a closing punctuation mark is never intended. */
            for mark in [",", ".", ";", ":", "!", "?"] {
                collapsed = collapsed.replacingOccurrences(of: " \(mark)", with: mark)
            }
            while collapsed.hasSuffix(" ") {
                collapsed.removeLast()
            }
            return collapsed
        }

        return lines.joined(separator: "\n")
    }
}
