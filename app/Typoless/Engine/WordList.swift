import AppKit

/**
 Whether a word is in the Mac's own dictionary for a language.

 What tells a grammar fix from a typo. "dem" to "des" and "helo" to "hello"
 are the same shape, one letter changed at the end, but the first starts from a
 real word and the second does not. Only a word list can say which is which,
 and the system's is already on every Mac, in every language the app corrects.

 The answer can differ slightly between Macs, since the system dictionary
 includes words the user taught it. That only ever moves a change between the
 grammar and typo rules, both of which are corrections.
 */
enum WordList {
    /**
     One lookup at a time. The spell checker is shared by the whole process
     and the corrections run off the main thread, so calls are serialised here
     rather than trusted to be safe side by side.
     */
    private static let lock = NSLock()

    static func contains(_ word: String, in language: CorrectionLanguage) -> Bool {
        guard !word.isEmpty, let code = dictionaryCode(for: language) else { return false }

        /**
         German nouns are only words with their capital, and every word may
         open a sentence, so the word counts if any of its common casings does.
         Never as written in capitals, though: the spell checker accepts any
         word in capitals as an acronym, "ENUMES" included.
         */
        let lowercased = word.lowercased()
        let capitalised = lowercased.prefix(1).uppercased() + lowercased.dropFirst()
        let isShouted = word.contains(where: \.isLetter) && !word.contains(where: \.isLowercase)
        let candidates = isShouted ? [lowercased, capitalised] : [word, lowercased, capitalised]

        lock.lock()
        defer { lock.unlock() }

        return candidates.contains { candidate in
            NSSpellChecker.shared.checkSpelling(
                of: candidate,
                startingAt: 0,
                language: code,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            ).location == NSNotFound
        }
    }

    /**
     Whether the user has taught this word to their Mac.

     A different question from whether it is a word, and a stronger one. The
     dictionary says what the language holds; this says what this person
     writes. "pnpm" is in no dictionary and is one edit from "ppm", which is in
     every dictionary, so the rules that fix a typo will happily make that
     change and call it a correction. Nothing but the user can settle it, and
     the user already has: "Learn Spelling" is in the menu of every Mac text
     field, and the answer belongs to the whole machine rather than to this
     app.

     Asked in the casings `contains` asks in, since a name taught in the middle
     of a sentence is still the same name when it opens one.
     */
    static func isLearned(_ word: String) -> Bool {
        let trimmed = String(withoutSurroundingMarks(word))

        guard !trimmed.isEmpty else { return false }

        let lowercased = trimmed.lowercased()
        let capitalised = lowercased.prefix(1).uppercased() + lowercased.dropFirst()

        lock.lock()
        defer { lock.unlock() }

        return [trimmed, lowercased, capitalised].contains {
            NSSpellChecker.shared.hasLearnedWord($0)
        }
    }

    /**
     Teaches the word to the Mac, or takes it back.

     Deliberately the system's list and not one of our own. A private list
     would protect the word here and nowhere else, and would be a second place
     the answer lives, which is how two answers start to disagree.
     */
    static func setLearned(_ isLearned: Bool, for word: String) {
        let trimmed = String(withoutSurroundingMarks(word))

        guard !trimmed.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        if isLearned {
            NSSpellChecker.shared.learnWord(trimmed)
        } else {
            NSSpellChecker.shared.unlearnWord(trimmed)
        }
    }

    /** The word without the punctuation a sentence puts around it. */
    private static func withoutSurroundingMarks(_ word: String) -> Substring {
        var trimmed = Substring(word)

        while let first = trimmed.first, !first.isLetter, !first.isNumber {
            trimmed = trimmed.dropFirst()
        }
        while let last = trimmed.last, !last.isLetter, !last.isNumber {
            trimmed = trimmed.dropLast()
        }

        return trimmed
    }

    /**
     The dictionary's name for a language. Some are only installed as a
     regional variant, Portuguese as `pt_PT` and `pt_BR`, so the bare code is
     not always one the spell checker knows.
     */
    private static func dictionaryCode(for language: CorrectionLanguage) -> String? {
        let code = language.nlLanguage.rawValue

        lock.lock()
        defer { lock.unlock() }

        let available = NSSpellChecker.shared.availableLanguages

        return available.first { $0 == code } ?? available.first { $0.hasPrefix(code + "_") }
    }
}
