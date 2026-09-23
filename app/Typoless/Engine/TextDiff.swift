import Foundation

/** One contiguous difference between the original text and a corrected version. */
struct TextEdit: Sendable, Equatable {
    let range: Range<String.Index>
    let original: String
    let replacement: String
}

/**
 Works out what actually changed between two versions of a text.

 The app never asks the model where its changes are. Small models are poor at
 character offsets, and a wrong offset silently corrupts text rather than
 failing loudly. Comparing the two strings is exact, costs nothing, and means
 the model only has to be good at the one thing it is good at: writing the
 corrected sentence.
 */
enum TextDiff {
    /**
     Compares runs of whitespace and runs of non-whitespace rather than
     characters, so a change lands on the word it belongs to and can be judged
     as a whole.
     */
    static func edits(from original: String, to corrected: String) -> [TextEdit] {
        let source = atoms(of: original)
        let target = atoms(of: corrected).map(\.text)

        guard !source.isEmpty || !target.isEmpty else { return [] }

        let sourceTexts = source.map(\.text)
        let common = longestCommonSubsequence(sourceTexts, target)

        var edits: [TextEdit] = []
        var sourceIndex = 0
        var targetIndex = 0

        /** Everything between two matched atoms is one edit, or several. */
        for match in common + [Match(source: source.count, target: target.count)] {
            let (sourceGap, targetGap) = trimmingUnchangedSpacing(
                sourceIndex..<match.source,
                targetIndex..<match.target,
                sourceTexts,
                target
            )

            for pair in pairing(sourceGap, targetGap, sourceTexts, target) {
                let changedSource = source[pair.source]
                let changedTarget = target[pair.target]
                let replacement = changedTarget.joined()

                guard changedSource.map(\.text).joined() != replacement else { continue }

                if let first = changedSource.first, let last = changedSource.last {
                    edits.append(
                        TextEdit(
                            range: first.range.lowerBound..<last.range.upperBound,
                            original: changedSource.map(\.text).joined(),
                            replacement: replacement
                        )
                    )
                } else if !replacement.isEmpty {
                    /**
                     Pure insertion, anchored where what follows it begins, which
                     is the spacing just trimmed rather than the matched word
                     beyond it.
                     */
                    let position = pair.source.lowerBound < source.count
                        ? source[pair.source.lowerBound].range.lowerBound
                        : original.endIndex
                    edits.append(
                        TextEdit(range: position..<position, original: "", replacement: replacement)
                    )
                }
            }

            sourceIndex = match.source + 1
            targetIndex = match.target + 1
        }

        return merging(edits, in: original)
    }

    /**
     Splits a gap into one change per word, where both sides hold the same number
     of words.

     Without this a gap is one change however much it spans, and a single
     untouchable word inside it takes the whole sentence down with it: a URL
     whose capitalisation the model altered sits between two ordinary fixes, and
     refusing the one change refuses all three. Where the words still correspond
     one to one, which is the ordinary case, each can be judged on its own.

     Where the counts differ the words no longer correspond, and pairing them by
     position would be the very mistake this file exists to avoid, so the gap
     stays whole and is judged as one change.
     */
    private static func pairing(
        _ sourceGap: Range<Int>,
        _ targetGap: Range<Int>,
        _ source: [String],
        _ target: [String]
    ) -> [(source: Range<Int>, target: Range<Int>)] {
        let sourceWords = sourceGap.filter { isAnchor(source[$0]) }
        let targetWords = targetGap.filter { isAnchor(target[$0]) }

        guard !sourceWords.isEmpty, sourceWords.count == targetWords.count else {
            return [(sourceGap, targetGap)]
        }

        var pairs: [(source: Range<Int>, target: Range<Int>)] = []
        var sourceStart = sourceGap.lowerBound
        var targetStart = targetGap.lowerBound

        for (sourceWord, targetWord) in zip(sourceWords, targetWords) {
            /** The spacing leading up to the word, which may differ on its own. */
            pairs.append((sourceStart..<sourceWord, targetStart..<targetWord))
            pairs.append((sourceWord..<(sourceWord + 1), targetWord..<(targetWord + 1)))
            sourceStart = sourceWord + 1
            targetStart = targetWord + 1
        }

        pairs.append((sourceStart..<sourceGap.upperBound, targetStart..<targetGap.upperBound))

        return pairs
    }

    /**
     Joins changes that are only separated by spacing.

     A word can be split in two by a correction: "tim,i" becomes "Tim, I". Left
     alone, that appears as one change to a word plus the insertion of another,
     and judging those separately allows the first and refuses the second, which
     silently deletes a word. Seen as a single change it is plainly just spacing
     and capitalisation.

     A space typed in the wrong place is the same problem the other way round:
     "shouldw e" becoming "should we" reads as one word losing a letter and
     another gaining one. Two neighbouring changes are joined when, taken
     together, they hold the same letters in the same order and only the
     spacing moved.
     */
    private static func merging(_ edits: [TextEdit], in text: String) -> [TextEdit] {
        var merged: [TextEdit] = []

        for edit in edits {
            guard
                let previous = merged.last,
                previous.range.upperBound <= edit.range.lowerBound
            else {
                merged.append(edit)
                continue
            }

            /**
             Only an insertion gets absorbed into its neighbour, or a pair that
             together only moves a space. Joining two substantive changes
             because a space happens to sit between them
             would chain unrelated corrections into one oversized change, which
             is then judged, and refused, as a whole.
             */
            let gap = text[previous.range.upperBound..<edit.range.lowerBound]
            let joined = TextEdit(
                range: previous.range.lowerBound..<edit.range.upperBound,
                original: previous.original + gap + edit.original,
                replacement: previous.replacement + gap + edit.replacement
            )

            guard
                gap.allSatisfy(\.isWhitespace),
                previous.original.isEmpty || edit.original.isEmpty || movesOnlySpacing(joined)
            else {
                merged.append(edit)
                continue
            }

            merged[merged.count - 1] = joined
        }

        return merged
    }

    /**
     A change with the marks it adds at either end taken off it, or the change
     itself where there are none.

     Changes are found one word at a time, which is the right size to judge and
     the wrong size to judge *partly*. `gruesse` becoming `grüße,` restores two
     umlauts and adds a comma in one change, so a user who turned commas off
     lost the umlauts with it. Between a fifth and two fifths of the changes
     refused for one switched-off rule also carried a rule the user still
     wanted, measured with noun capitals, commas and apostrophes switched off in
     turn.

     Only marks at the edges, and never a cut through the letters. Cutting by
     character was tried first and is not safe: `gruesse` to `grüße,` aligns as
     `u` becoming `üß` and `sse` becoming `,`, so keeping the half that is
     allowed writes `grüßesse` into the user's text. A mark at the edge is the
     one piece that is separable by construction, since taking it off leaves the
     word the model wrote.

     The pieces are checked against the change they came from before they are
     handed back: applied together they must produce exactly what it produced,
     or nothing is cut. Nothing that reaches the user's text is assembled from a
     guess.
     */
    static func splitting(_ edit: TextEdit, in text: String) -> [TextEdit] {
        guard !edit.original.isEmpty, !edit.replacement.isEmpty else { return [edit] }

        var core = Substring(edit.replacement)
        var trailing = ""
        var leading = ""

        /** Only where the user wrote no mark there, so nothing existing is peeled off. */
        if let last = edit.original.last, !isMark(last) {
            while let mark = core.last, isMark(mark) {
                trailing.insert(mark, at: trailing.startIndex)
                core = core.dropLast()
            }
        }

        if let first = edit.original.first, !isMark(first) {
            while let mark = core.first, isMark(mark) {
                leading.append(mark)
                core = core.dropFirst()
            }
        }

        guard !leading.isEmpty || !trailing.isEmpty, !core.isEmpty else { return [edit] }

        var parts: [TextEdit] = []

        if !leading.isEmpty {
            parts.append(
                TextEdit(
                    range: edit.range.lowerBound..<edit.range.lowerBound,
                    original: "",
                    replacement: leading
                )
            )
        }

        if core != edit.original {
            parts.append(TextEdit(range: edit.range, original: edit.original, replacement: String(core)))
        }

        if !trailing.isEmpty {
            parts.append(
                TextEdit(
                    range: edit.range.upperBound..<edit.range.upperBound,
                    original: "",
                    replacement: trailing
                )
            )
        }

        guard apply(parts, to: text) == apply([edit], to: text) else { return [edit] }

        return parts
    }

    /** A mark writing uses, as opposed to a letter, a digit or spacing. */
    private static func isMark(_ character: Character) -> Bool {
        character.isPunctuation || character.isSymbol
    }

    /** Whether a change keeps every other character and only moves or changes whitespace. */
    private static func movesOnlySpacing(_ edit: TextEdit) -> Bool {
        edit.original.filter { !$0.isWhitespace } == edit.replacement.filter { !$0.isWhitespace }
    }

    /** Applies edits back to front, so earlier ranges stay valid as later ones change. */
    static func apply(_ edits: [TextEdit], to text: String) -> String {
        var result = text

        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceSubrange(edit.range, with: edit.replacement)
        }

        return result
    }

    /**
     The single span where two versions of a text differ, in UTF-16 offsets.

     Trims the matching head and tail rather than describing the whole string, so
     putting one version back over the other touches as little of the field as
     possible. Nil when the two are identical.

     Deliberately coarser than `edits(from:to:)`: this describes one span
     covering every difference, which is what an undo wants, whereas the diff
     describes each difference separately, which is what an edit wants.
     */
    static func differingSpan(from before: String, to after: String) -> (range: CFRange, replacement: String)? {
        /**
         Compared character by character, not UTF-16 unit by unit.

         Trimming over raw units left the boundary inside a surrogate pair
         whenever two non-BMP characters shared a lead unit, and decoding the
         orphaned half produced U+FFFD. Undo hands this span straight to the
         writer, so the replacement character went into the user's live field.
         */
        let source = Array(before)
        let target = Array(after)

        var head = 0
        while head < source.count, head < target.count, source[head] == target[head] {
            head += 1
        }

        var tail = 0
        while
            tail < source.count - head,
            tail < target.count - head,
            source[source.count - 1 - tail] == target[target.count - 1 - tail] {
            tail += 1
        }

        let removed = source.count - head - tail
        let replacement = String(target[head..<(target.count - tail)])

        guard removed > 0 || !replacement.isEmpty else { return nil }

        /** Offsets are handed to the accessibility API, which counts in UTF-16. */
        let start = before.index(before.startIndex, offsetBy: head)
        let end = before.index(before.endIndex, offsetBy: -tail)

        let location = start.utf16Offset(in: before)

        return (
            CFRange(location: location, length: end.utf16Offset(in: before) - location),
            replacement
        )
    }

    private struct Atom {
        let text: String
        let range: Range<String.Index>
    }

    private struct Match {
        let source: Int
        let target: Int
    }

    private static func atoms(of text: String) -> [Atom] {
        var result: [Atom] = []
        var index = text.startIndex

        while index < text.endIndex {
            let isWhitespace = text[index].isWhitespace
            var end = index

            while end < text.endIndex, text[end].isWhitespace == isWhitespace {
                end = text.index(after: end)
            }

            result.append(Atom(text: String(text[index..<end]), range: index..<end))
            index = end
        }

        return result
    }

    /**
     Whether an atom may anchor the alignment, which words may and spacing may not.

     Every run of whitespace looks like every other one, so a subsequence is free
     to pair any space with any space, and prefers to: there are many of them and
     each one matched is another atom in common. The alignment then slips by a
     word, and the diff reports that the user's own word should become a
     different word. That is refused, correctly, and the real corrections in the
     same sentence go down with it.
     */
    private static func isAnchor(_ atom: String) -> Bool {
        atom.first.map { !$0.isWhitespace } ?? false
    }

    /**
     Gives back the spacing on either side of a change that did not change.

     Spacing takes no part in the alignment, so it all falls into the gaps
     between matched words, and a gap that begins and ends with the same spacing
     on both sides describes an edit larger than what actually differs. Trimming
     from the ends is safe where matching in the middle was not: a matched word
     pins the end of the gap, so there is only one way to read the spacing next
     to it.
     */
    private static func trimmingUnchangedSpacing(
        _ sourceGap: Range<Int>,
        _ targetGap: Range<Int>,
        _ source: [String],
        _ target: [String]
    ) -> (source: Range<Int>, target: Range<Int>) {
        var sourceGap = sourceGap
        var targetGap = targetGap

        while
            !sourceGap.isEmpty, !targetGap.isEmpty,
            source[sourceGap.lowerBound] == target[targetGap.lowerBound] {
            sourceGap = (sourceGap.lowerBound + 1)..<sourceGap.upperBound
            targetGap = (targetGap.lowerBound + 1)..<targetGap.upperBound
        }

        while
            !sourceGap.isEmpty, !targetGap.isEmpty,
            source[sourceGap.upperBound - 1] == target[targetGap.upperBound - 1] {
            sourceGap = sourceGap.lowerBound..<(sourceGap.upperBound - 1)
            targetGap = targetGap.lowerBound..<(targetGap.upperBound - 1)
        }

        return (sourceGap, targetGap)
    }

    private static func longestCommonSubsequence(_ source: [String], _ target: [String]) -> [Match] {
        guard !source.isEmpty, !target.isEmpty else { return [] }

        var lengths = Array(
            repeating: Array(repeating: 0, count: target.count + 1),
            count: source.count + 1
        )

        for i in stride(from: source.count - 1, through: 0, by: -1) {
            for j in stride(from: target.count - 1, through: 0, by: -1) {
                lengths[i][j] = source[i] == target[j] && isAnchor(source[i])
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }

        var matches: [Match] = []
        var i = 0
        var j = 0

        while i < source.count, j < target.count {
            if source[i] == target[j], isAnchor(source[i]) {
                matches.append(Match(source: i, target: j))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }

        return matches
    }
}
