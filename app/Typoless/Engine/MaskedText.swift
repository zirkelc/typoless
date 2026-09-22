import Foundation

/**
 A chunk with its untouchable parts swapped for placeholders before the model
 ever sees it.

 The spans in question were already known: `ProtectedSpans` finds them so that
 edits landing inside one can be vetoed. But that veto is applied to the
 model's answer, so the model was still shown the URL, and a URL does far more
 damage on the way in than on the way out. Measured on Apple's on-device model,
 one German line containing a link had its plain spelling mistake corrected in
 zero of ninety-six attempts across every prompt wording; the same line with
 the link taken out was corrected every time by the better wordings. The link
 does not merely survive the pass, it costs the pass.

 So the spans are replaced by short markers, the model corrects the prose
 around them, and the originals go back afterwards, character for character.
 The model cannot damage what it was never shown.

 Restoring is where this has to be careful rather than clever. If a marker does
 not come back exactly once, the reply cannot be mapped onto the original with
 any confidence, so `restore` refuses rather than guessing, and the caller asks
 again without the markers. No marker survives every sentence, so that fallback
 is what makes hiding them safe to do at all.
 */
struct MaskedText {
    /** What the model is shown. */
    let text: String

    /** What each marker stands for, in the order they appear. */
    private let originals: [String]

    /**
     The marker put in place of one span.

     Chosen by measurement, and the measurement was worth doing: of eight
     candidates tried against the sentences that break them, the bracketed
     forms were the worst. `⟦0⟧` came back intact in none of six replies. The
     model does not treat an unusual bracket as an opaque token, it treats it
     as a mistake and tidies it away, returning a bare `0`, or `<code>0</code>`,
     or in one case replacing the whole thing with `him`. Three letters and a
     digit read as a name instead, and are left alone.

     The digit is what keeps two spans in one chunk apart, so a message with a
     link and a handle puts each back where it belongs rather than swapping
     them.
     */
    static func marker(_ index: Int) -> String { "ZQX\(index)" }

    /** Whether anything was hidden, so the caller can skip the work when not. */
    var hidesNothing: Bool { originals.isEmpty }

    static func mask(_ text: String, protecting spans: [Range<String.Index>]) -> MaskedText {
        let spans = merged(spans)

        guard !spans.isEmpty else { return MaskedText(text: text, originals: []) }

        var masked = ""
        var originals: [String] = []
        var cursor = text.startIndex

        for span in spans {
            masked += text[cursor..<span.lowerBound]
            masked += marker(originals.count)
            originals.append(String(text[span]))
            cursor = span.upperBound
        }

        masked += text[cursor...]

        return MaskedText(text: masked, originals: originals)
    }

    /**
     Puts the hidden spans back into the model's reply.

     Nil when any marker failed to come back exactly once. A model that dropped
     one would otherwise have the user's link silently deleted, and one that
     repeated it would have it duplicated, and neither is something to paper
     over.

     Highest marker first, because `ZQX1` reads as the opening of `ZQX10`. In
     ascending order a message with eleven hidden spans finds the low marker
     twice, counts that as ambiguous and throws away a chunk that was perfectly
     restorable. Taking the long ones first leaves nothing for the short ones
     to collide with.
     */
    func restore(_ reply: String) -> String? {
        var restored = reply

        for (index, original) in zip(originals.indices, originals).reversed() {
            let marker = Self.marker(index)

            /**
             Case-insensitively, because a marker sitting where a sentence
             starts comes back capitalised, and `Zqx0` names the same span
             `ZQX0` does. Refusing that would throw the chunk away over the one
             thing the model was asked to fix.
             */
            let matches = restored.ranges(of: marker, options: .caseInsensitive)

            guard matches.count == 1, let match = matches.first else { return nil }

            restored = restored.replacingCharacters(in: match, with: original)
        }

        return restored
    }

    /**
     Overlapping spans flattened into disjoint ones.

     They arrive overlapping as a matter of course, since a link is found both
     by its pattern and by the data detector, and emoji are reported one
     character at a time. Masking them as they come would nest one marker
     inside another and lose the text between.
     */
    private static func merged(_ spans: [Range<String.Index>]) -> [Range<String.Index>] {
        var merged: [Range<String.Index>] = []

        for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) where !span.isEmpty {
            guard let last = merged.last, span.lowerBound <= last.upperBound else {
                merged.append(span)
                continue
            }

            merged[merged.count - 1] = last.lowerBound..<Swift.max(last.upperBound, span.upperBound)
        }

        return merged
    }
}

private extension String {
    /** Every place a marker occurs, so more than one can be told from exactly one. */
    func ranges(of needle: String, options: String.CompareOptions) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var searchFrom = startIndex

        while let match = range(of: needle, options: options, range: searchFrom..<endIndex) {
            found.append(match)
            searchFrom = match.upperBound
        }

        return found
    }
}
