import Foundation

/** One contiguous difference between the original text and a corrected version. */
struct TextEdit: Sendable {
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

        let common = longestCommonSubsequence(source.map(\.text), target)

        var edits: [TextEdit] = []
        var sourceIndex = 0
        var targetIndex = 0

        /** Everything between two matched atoms is one edit. */
        for match in common + [Match(source: source.count, target: target.count)] {
            let changedSource = source[sourceIndex..<match.source]
            let changedTarget = target[targetIndex..<match.target]

            if !changedSource.isEmpty || !changedTarget.isEmpty {
                let replacement = changedTarget.joined()

                if let first = changedSource.first, let last = changedSource.last {
                    let range = first.range.lowerBound..<last.range.upperBound
                    edits.append(
                        TextEdit(
                            range: range,
                            original: changedSource.map(\.text).joined(),
                            replacement: replacement
                        )
                    )
                } else if !replacement.isEmpty {
                    /** Pure insertion, anchored where the next matched atom starts. */
                    let position = match.source < source.count
                        ? source[match.source].range.lowerBound
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
     Joins changes that are only separated by spacing.

     A word can be split in two by a correction: "tim,i" becomes "Tim, I". Left
     alone, that appears as one change to a word plus the insertion of another,
     and judging those separately allows the first and refuses the second, which
     silently deletes a word. Seen as a single change it is plainly just spacing
     and capitalisation.
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
             Only an insertion gets absorbed into its neighbour. Joining two
             substantive changes because a space happens to sit between them
             would chain unrelated corrections into one oversized change, which
             is then judged, and refused, as a whole.
             */
            let gap = text[previous.range.upperBound..<edit.range.lowerBound]
            guard
                gap.allSatisfy(\.isWhitespace),
                previous.original.isEmpty || edit.original.isEmpty
            else {
                merged.append(edit)
                continue
            }

            merged[merged.count - 1] = TextEdit(
                range: previous.range.lowerBound..<edit.range.upperBound,
                original: previous.original + gap + edit.original,
                replacement: previous.replacement + gap + edit.replacement
            )
        }

        return merged
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
        let source = Array(before.utf16)
        let target = Array(after.utf16)

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

        let length = source.count - head - tail
        let replacement = target[head..<(target.count - tail)]

        guard length > 0 || !replacement.isEmpty else { return nil }

        return (
            CFRange(location: head, length: length),
            String(decoding: replacement, as: UTF16.self)
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

    private static func longestCommonSubsequence(_ source: [String], _ target: [String]) -> [Match] {
        guard !source.isEmpty, !target.isEmpty else { return [] }

        var lengths = Array(
            repeating: Array(repeating: 0, count: target.count + 1),
            count: source.count + 1
        )

        for i in stride(from: source.count - 1, through: 0, by: -1) {
            for j in stride(from: target.count - 1, through: 0, by: -1) {
                lengths[i][j] = source[i] == target[j]
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }

        var matches: [Match] = []
        var i = 0
        var j = 0

        while i < source.count, j < target.count {
            if source[i] == target[j] {
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
