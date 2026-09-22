import Foundation

/**
 Turns text into corrected text.

 The seam that keeps the on-device model from spreading through the app: the
 engine, the accessibility layer and the UI never learn which backend is behind
 this, which is what lets a different one be swapped in and a fake one be used
 in tests.
 */
protocol Corrector: Sendable {
    /**
     The changes to make, rather than the text with them already made.

     Returning edits instead of a finished string is what lets the app write
     back only the words it actually changed. A field holding a mention, a link
     or any other formatting keeps all of it, because the characters carrying it
     are never touched. Handing back a whole corrected string would force the
     caller to overwrite the field entirely, and everything in it that is not
     plain characters would be lost on the way.
     */
    func corrections(for text: String, settings: AppSettings) async throws -> [TextEdit]
}

extension Corrector {
    /** The corrected text, for callers that want the result rather than the changes. */
    func correct(_ text: String, settings: AppSettings = .permissive) async throws -> String {
        TextDiff.apply(try await corrections(for: text, settings: settings), to: text)
    }
}

/**
 Fixes only spacing, and only where it is unambiguous.

 Stands in until the model backend lands. Deliberately the most boring member of
 the four edit kinds the app is allowed to make: it needs no model, cannot
 change a word, and still proves the whole path from trigger to written-back
 text.
 */
struct WhitespaceCorrector: Corrector {
    func corrections(for text: String, settings: AppSettings) async throws -> [TextEdit] {
        TextDiff.edits(from: text, to: collapsed(text))
    }

    private func collapsed(_ text: String) -> String {
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
