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
         */
        let lowercased = word.lowercased()
        let candidates = [word, lowercased, lowercased.prefix(1).uppercased() + lowercased.dropFirst()]

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
