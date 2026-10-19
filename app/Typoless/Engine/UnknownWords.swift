import Foundation
import Observation

/**
 Words the user writes that no dictionary knows.

 A tool, a product, a surname, a codename from work: the Mac has never heard of
 any of them, and each one is a few letters from a word it has heard of, so the
 rules that fix a typo are happy to make that change and call it a correction.
 "pnpm" becomes "ppm". The user can stop it, by teaching the word to their Mac
 from the history window, but only for a word they happened to notice.

 This is the half that does not need noticing. The same word, written again and
 again and never in any dictionary, is somebody's vocabulary rather than
 somebody's slip. A typo is not repeated five times; a tool you work with every
 day is written five times before lunch.

 **Counted in memory and never written to disk.** The list is short and it is
 made of names, which is as personal as anything this app sees. It lives as
 long as the app does, which is long enough: a word has to reach five uses, and
 anything that does not reach five was not worth asking about.

 Nothing is ever applied from here. Each word is a question, answered in
 settings, and the answer goes to the Mac's own dictionary, where it holds for
 every app and can be taken back.
 */
@MainActor
@Observable
final class UnknownWords {
    /**
     How often a word must appear before it is worth asking about.

     Five, because a slip is not repeated five times and a word somebody
     works with is. Lower and the list fills with typos, which is the one
     thing that would make it worth nobody's attention.
     */
    private static let threshold = 5

    /** Words shorter than this are initials, units and noise. */
    private static let shortestWord = 3

    /** A ceiling on the whole thing, since a long day should not grow a list. */
    private static let limit = 500

    /** Unique words per pass, so one message cannot carry a word to five on its own. */
    private static let wordsPerPass = 200

    private var counts: [String: Int] = [:]
    private var dismissed: Set<String> = []

    /**
     Counts the words of one pass.

     The text as the user wrote it, not the correction, since the question is
     which words they chose.
     */
    func record(_ text: String, in language: CorrectionLanguage?) {
        guard let language else { return }

        var seen: Set<String> = []

        for word in text.split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" }) {
            guard seen.count < Self.wordsPerPass else { break }

            let candidate = String(word)

            guard candidate.count >= Self.shortestWord,
                  !seen.contains(candidate.lowercased()),
                  !WordList.contains(candidate, in: language),
                  !WordList.isLearned(candidate)
            else { continue }

            seen.insert(candidate.lowercased())

            guard counts.count < Self.limit || counts[candidate] != nil else { continue }

            counts[candidate, default: 0] += 1
        }
    }

    /**
     The words worth asking about, the most written first.

     Asked of the dictionary again rather than trusted from when they were
     counted: the user may have taught the Mac the word in the meantime, from
     the history window or from any other app, and a question they have already
     answered should not be put to them twice.
     */
    var suggestions: [String] {
        counts
            .filter { $0.value >= Self.threshold }
            .filter { !dismissed.contains($0.key) }
            .filter { !WordList.isLearned($0.key) }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map(\.key)
    }

    /** How often the user has written it, which is the whole argument for asking. */
    func count(of word: String) -> Int { counts[word] ?? 0 }

    /** Not that word. Asked once is enough, and the count stays in case it is useful. */
    func dismiss(_ word: String) {
        dismissed.insert(word)
    }

    #if DEBUG
    /**
     Words to look at the settings row with.

     The real list takes a week of somebody's writing to fill, which is a long
     time to wait to find out that a row is laid out wrongly.
     */
    func addSamples() {
        counts = ["pnpm": 12, "oxlint": 7, "flyweight": 6]
    }
    #endif
}
