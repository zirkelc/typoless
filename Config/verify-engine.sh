#!/bin/bash
#
# Checks the parts of the engine that decide what a correction does.
#
# The rules covered here are the app's central promise, and they are pure
# functions of a couple of strings, so they are worth checking without a
# running app or a model. Run from the repo root:
#
#     ./Config/verify-engine.sh
#
# This concatenates the engine sources with the cases below and runs them as a
# script. It stands in for a real test target, which the project does not have
# yet.

set -euo pipefail
cd "$(dirname "$0")/.."

# Left behind on purpose. This lives under the system temp directory, which is
# cleaned up on its own, and deleting it here would mean a recursive delete in
# a script that runs unattended.
SCRATCH=$(mktemp -d)
SOURCE="$SCRATCH/verify.swift"

cat \
    Spellbee/Support/Log.swift \
    Spellbee/Engine/TextDiff.swift \
    Spellbee/Engine/CorrectionRule.swift \
    Spellbee/Engine/EditGuardrail.swift \
    Spellbee/Engine/ProtectedSpans.swift \
    Spellbee/Engine/MaskedText.swift \
    Spellbee/History/IssueReport.swift \
    Spellbee/Engine/CorrectionDeadline.swift \
    Spellbee/Engine/ModelReplyCleaner.swift \
    Spellbee/Accessibility/FieldEdit.swift \
    Spellbee/Accessibility/AppPolicy.swift \
    Spellbee/Engine/TextChunker.swift \
    Spellbee/Accessibility/WriteScope.swift \
    Spellbee/History/TextExcerpt.swift \
    > "$SOURCE"

cat >> "$SOURCE" <<'SWIFT'

var failures = 0

/// Runs the text the user wrote and the text the model returned through the
/// guardrail, and checks what the field would end up containing.
func check(
    _ name: String,
    _ original: String,
    _ modelOutput: String,
    allowing rules: Set<CorrectionRule> = Set(CorrectionRule.allCases),
    expect: String
) {
    let protected = ProtectedSpans.find(in: original)
    let verdict = EditGuardrail.filter(
        TextDiff.edits(from: original, to: modelOutput),
        in: original,
        allowing: rules,
        protectedBy: protected
    )
    let result = verdict.isTrustworthy ? TextDiff.apply(verdict.accepted, to: original) : original
    let ok = result == expect
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { print("        got: \(result)\n   expected: \(expect)") }
}

print("== corrections applied ==")
check("casing + apostrophe", "i think its ready", "I think it's ready", expect: "I think it's ready")
check("double space", "hello  world", "hello world", expect: "hello world")
check("space before comma", "hello , world", "hello, world", expect: "hello, world")
check("missing period + caps", "hello world", "Hello world.", expect: "Hello world.")
check("typo", "teh cat sat", "the cat sat", expect: "the cat sat")
check("your/you're", "i hope your well", "I hope you're well", expect: "I hope you're well")
check("german caps", "wir gehen ins kino", "Wir gehen ins Kino", expect: "Wir gehen ins Kino")
check("german sharp s", "das war grosse klasse", "Das war große Klasse.", expect: "Das war große Klasse.")
check("missing comma", "if you can come let me know", "If you can come, let me know", expect: "If you can come, let me know")
check("umlaut restored", "wir treffen uns im buero", "Wir treffen uns im Büro", expect: "Wir treffen uns im Büro")
check("umlaut plus comma", "koenntest du das pruefen bevor wir abschicken", "Könntest du das prüfen, bevor wir abschicken", expect: "Könntest du das prüfen, bevor wir abschicken")
check("eszett restored", "das war eine grosse hilfe", "Das war eine große Hilfe", expect: "Das war eine große Hilfe")
check("word split by punctuation", "hi tim,i hope your  well", "Hi Tim, I hope you're well.", expect: "Hi Tim, I hope you're well.")

check("transposed letters plus a capital", "the meeting is on wendesday at three", "The meeting is on Wednesday at three", expect: "The meeting is on Wednesday at three")

/// A space is not an anchor.
///
/// Every run of whitespace is the same single space, so a longest common
/// subsequence over atoms is free to match any space to any other one, and it
/// prefers doing so: matching spaces is cheap and there are many of them. The
/// alignment then slips by one word and the diff reports that the user's
/// "mistake" should become "my", which the guardrail refuses, correctly, taking
/// the real corrections down with it. Only words anchor the alignment now.
check(
    "punctuation and spacing fixed in one sentence",
    "sorry ,my mistake . i will redo it .",
    "Sorry, my mistake. I will redo it.",
    expect: "Sorry, my mistake. I will redo it."
)
check(
    "several spaces before commas",
    "thanks , and yes , that works",
    "Thanks, and yes, that works",
    expect: "Thanks, and yes, that works"
)
/// A doubled word is still a word, and removing one is still a deletion, so the
/// alignment has to survive the repetition without the guardrail's answer
/// changing. It refuses, as it refuses every deletion. That is deliberate: the
/// same shape covers "the the" and a word the user meant to repeat.
check(
    "a doubled word is not removed, even where the words around it repeat",
    "the the same the same day",
    "The same the same day",
    expect: "the the same the same day"
)

print("\n== rewriting refused, wording preserved ==")
check("word inserted", "hello world", "hello beautiful world", expect: "hello world")
check("word deleted", "i am very tired", "I am tired", expect: "I am very tired")
check("synonym swap", "that is good", "That is excellent", expect: "That is good")
check("meaning change", "the meeting is at 5", "The meeting was at 5", expect: "The meeting is at 5")
check("umlaut fold is not a licence", "wir fahren nach hause", "Wir fahren nach Häuserblock", expect: "Wir fahren nach hause")

// Ignoring case in the spelling distance must not turn a word swap into a typo.
check("pronoun swap", "Passt dir Dienstag um 10 Uhr?", "Passt ihr Dienstag um 10 Uhr?", expect: "Passt dir Dienstag um 10 Uhr?")
check("word lengthened", "The deploy finished at 14:32", "The deployment finished at 14:32", expect: "The deploy finished at 14:32")
check("different word, same first letter", "sie ist schon hier", "sie hat schon hier", expect: "sie ist schon hier")

print("\n== every rule is told apart ==")

/// The classifier now names which question a change is, not just that it is a
/// punctuation one, because "add a comma" and "add a full stop" are not the
/// same decision and people want to answer them differently.
func checkRule(_ name: String, _ original: String, _ corrected: String, expect: CorrectionRule?) {
    checkRules(name, original, corrected, expect: expect.map { [$0] } ?? [])
}

/// An edit can raise more than one question at once, and every one of them has
/// to be permitted before it is applied. Restoring an umlaut while also adding a
/// comma used to report only the umlaut, so the comma setting was never asked.
func checkRules(_ name: String, _ original: String, _ corrected: String, expect: Set<CorrectionRule>) {
    let edits = TextDiff.edits(from: original, to: corrected)
    let kinds = edits.map { EditGuardrail.classify($0, in: original) }
    let got = kinds.count == 1 ? (kinds[0] ?? []) : []
    let ok = got == expect
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok {
        print("        got: \(got.map(\.rawValue).sorted())\n   expected: \(expect.map(\.rawValue).sorted())")
    }
}

checkRule("spacing", "hello  world", "hello world", expect: .spacing)
checkRule("sentence capital", "hello there", "Hello there", expect: .capitalisation)
checkRule("capital after a full stop", "done. whats next", "done. Whats next", expect: .capitalisation)
checkRule("noun capital mid-sentence", "ein test", "ein Test", expect: .nounCapitalisation)
checkRule("comma", "well done everyone", "well done, everyone", expect: .commas)
checkRule("apostrophe", "its ready", "it\'s ready", expect: .apostrophes)
checkRule("curly apostrophe", "its ready", "it\u{2019}s ready", expect: .apostrophes)
checkRule("full stop at the end", "see you tomorrow", "see you tomorrow.", expect: .sentenceEndings)
checkRule("other punctuation", "really?!", "really?", expect: .otherPunctuation)
checkRule("umlaut", "gruesse", "grüße", expect: .umlauts)
checkRule("typo", "teh meeting", "the meeting", expect: .typos)
checkRule("not a correction", "the meeting", "the appointment", expect: nil)

print("\n== a language turns off the rules it does not want ==")

check("commas off", "well done everyone", "Well done, everyone",
      allowing: [.capitalisation, .typos], expect: "Well done everyone")
check("noun capitals off, sentence capitals on", "hallo, das ist ein test", "Hallo, das ist ein Test",
      allowing: [.capitalisation], expect: "Hallo, das ist ein test")
check("umlauts off does not stop typos", "gruesse aus muenchen", "grüße aus münchen",
      allowing: [.typos], expect: "gruesse aus muenchen")
check("sentence endings off", "see you tomorrow", "See you tomorrow.",
      allowing: [.capitalisation, .typos, .commas], expect: "See you tomorrow")
check("sentence endings on", "see you tomorrow", "See you tomorrow.",
      allowing: [.capitalisation, .sentenceEndings], expect: "See you tomorrow.")
check("declining a rule does not poison the chunk", "hi anna, teh deploy ist durch", "Hi Anna, the deploy ist durch",
      allowing: [.capitalisation, .nounCapitalisation], expect: "Hi Anna, teh deploy ist durch")

// A name in the middle of a sentence is a noun capital as far as this can tell,
// because position is the only evidence it has: nothing here knows "Anna" is a
// person and "test" is not. So turning noun capitals off in German also stops
// proper nouns being capitalised mid-sentence. Pinned rather than hidden.
check("a name mid-sentence counts as a noun capital", "hi anna", "Hi Anna",
      allowing: [.capitalisation], expect: "Hi anna")

print("\n== known gap, pinned so it cannot change unnoticed ==")

// A word whose ending changes within two edits reads as a typo to the distance
// rule, so "hause" becomes "häuser" and the sentence now says something else.
// This was never blocked on its merits: before the spelling distance ignored
// case, the same change was refused when a model capitalised it and accepted
// when it did not. Closing it needs a rule about word endings, not a budget.
check("word ending changed within budget", "wir fahren nach hause", "wir fahren nach häuser", expect: "wir fahren nach häuser")

/// A rewrite of one phrase, alongside a capital that is genuinely a correction.
///
/// The capital lands and the rewrite does not, which is what the four checks
/// above ask for in the same situation. It used to be refused outright, and the
/// only thing that made this case different was that the alignment happened to
/// split the rewritten phrase into two changes rather than one, so it crossed
/// the trust threshold by an accident of where the words lined up. Whether a
/// pass is trusted should not turn on that.
check(
    "one phrase rewritten, the capital still lands",
    "the meeting is at 5",
    "The meeting has been scheduled for 5",
    expect: "The meeting is at 5"
)

print("\n== whole chunk refused ==")
check("translation", "wir gehen ins kino", "we are going to the cinema", expect: "wir gehen ins kino")
check("mostly rewritten", "can you send it over when your done", "Please forward it once you have finished.", expect: "can you send it over when your done")
check("model answered instead", "what is the capital of france", "The capital of France is Paris.", expect: "what is the capital of france")

print("\n== symbols are content, not punctuation ==")

// Stripping symbols alongside punctuation made every symbol interchangeable
// with every other, so a money amount and the tone of a message were both one
// unremarkable "punctuation change" away from being rewritten.
check("emoji swap", "We shipped it 🎉", "We shipped it 😀", expect: "We shipped it 🎉")
check("currency swap", "Kosten: 5 € netto", "Kosten: 5 $ netto", expect: "Kosten: 5 € netto")
check("corrections around an emoji still land", "i think its ready 🎉", "I think it's ready 🎉", expect: "I think it's ready 🎉")
check("corrections around a currency still land", "das kostet 5 € netto", "Das kostet 5 € netto", expect: "Das kostet 5 € netto")

print("\n== a typo stays in its own alphabet ==")

check("junk appended", "Danke", "Danke\u{D00E}4", expect: "Danke")
check("latin accents are not another alphabet", "gruesse aus muenchen", "Grüße aus München", expect: "Grüße aus München")

print("\n== protected spans ==")
check("url untouched", "check http://foo.com/Bar now", "Check http://foo.com/bar now.", expect: "Check http://foo.com/Bar now.")
check("handle untouched", "ask @chris.cook about it", "Ask @Chris.Cook about it.", expect: "Ask @chris.cook about it.")
check("code untouched", "call `getFoo` first", "Call `getfoo` first.", expect: "Call `getFoo` first.")
check("email untouched", "mail me at Chris@Foo.com ok", "Mail me at chris@foo.com ok.", expect: "Mail me at Chris@Foo.com ok.")

print("\n== unwrapping a free-text model reply ==")

func checkClean(_ name: String, _ reply: String, expect: String) {
    let result = ModelReplyCleaner.clean(reply)
    let ok = result == expect
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { print("        got: \(result)\n   expected: \(expect)") }
}

checkClean("plain", "Hello world.", expect: "Hello world.")
checkClean("reasoning block", "<think>The user wants...</think>\nHello world.", expect: "Hello world.")
checkClean("preamble", "Here is the corrected text:\n\nHello world.", expect: "Hello world.")
checkClean("quoted", "\"Hello world.\"", expect: "Hello world.")
checkClean("fenced", "```\nHello world.\n```", expect: "Hello world.")
checkClean("reasoning and preamble", "<think>hmm</think>\n\nCorrected:\n\nHello world.", expect: "Hello world.")
checkClean("keeps an inner quote", "She said \"hello\" to me.", expect: "She said \"hello\" to me.")
checkClean("keeps a real blank line", "Hello world.", expect: "Hello world.")

print("\n== changes stay minimal ==")

/// Checks that a correction touches only the words it had to.
///
/// This is what lets the app write back without flattening a field: the
/// characters carrying a mention, a link or any other formatting are never
/// part of an edit, so they are never rewritten.
func checkEdits(_ name: String, _ original: String, _ corrected: String, expect: [String]) {
    let edits = TextDiff.edits(from: original, to: corrected)
    let touched = edits.map(\.original)
    let ok = touched == expect
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { print("        got: \(touched)\n   expected: \(expect)") }
}

checkEdits(
    "one word in a long line",
    "hey @chris, can you check teh deploy on https://ci.example.com today",
    "hey @chris, can you check the deploy on https://ci.example.com today",
    expect: ["teh"]
)
checkEdits(
    "two far apart",
    "i went to teh shop and bougth milk",
    "I went to the shop and bought milk",
    expect: ["i", "teh", "bougth"]
)
checkEdits("nothing to do", "All good here.", "All good here.", expect: [])
checkEdits(
    "trailing punctuation only",
    "see you tomorrow",
    "see you tomorrow.",
    expect: ["tomorrow"]
)

print("\n== the span an undo has to put back ==")

func checkSpan(_ name: String, from before: String, to after: String, expect: (Int, Int, String)?) {
    let span = TextDiff.differingSpan(from: before, to: after)
    let got = span.map { ($0.range.location, $0.range.length, $0.replacement) }
    let ok = got?.0 == expect?.0 && got?.1 == expect?.1 && got?.2 == expect?.2
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { print("        got: \(String(describing: got))\n   expected: \(String(describing: expect))") }
}

checkSpan("identical", from: "same", to: "same", expect: nil)
checkSpan("one word", from: "the cat sat", to: "the dog sat", expect: (4, 3, "dog"))
checkSpan("insertion", from: "hello world", to: "hello big world", expect: (6, 0, "big "))
checkSpan("deletion", from: "hello big world", to: "hello world", expect: (6, 4, ""))
checkSpan("shared letters at both ends", from: "recieve", to: "receive", expect: (3, 2, "ei"))

print("\n== positions after the changes land ==")

func checkCaret(_ name: String, _ edits: [FieldEdit], from offset: Int, expect: Int) {
    let result = edits.caretPosition(from: offset)
    let ok = result == expect
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { print("        got: \(result)\n   expected: \(expect)") }
}

/// "teh cat" -> "the cats": one same-length fix early, one growth later.
let sample = [
    FieldEdit(range: CFRange(location: 0, length: 3), replacement: "the"),
    FieldEdit(range: CFRange(location: 4, length: 3), replacement: "cats"),
]

checkCaret("before every change", sample, from: 0, expect: 0)
checkCaret("between them", sample, from: 4, expect: 4)
checkCaret("after both", sample, from: 7, expect: 8)
checkCaret("inside a changed word", sample, from: 5, expect: 8)
checkCaret("no changes at all", [], from: 12, expect: 12)

func checkLanded(_ name: String, _ edits: [FieldEdit], expect: [(Int, Int)]) {
    let ranges = edits.landedRanges.map { ($0.location, $0.length) }
    let ok = ranges.count == expect.count && zip(ranges, expect).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { print("        got: \(ranges)\n   expected: \(expect)") }
}

checkLanded("displaced by what came before", sample, expect: [(0, 3), (4, 4)])
checkLanded(
    "pure deletion has nothing to point at",
    [FieldEdit(range: CFRange(location: 5, length: 1), replacement: "")],
    expect: []
)
checkLanded(
    "later change shifted by an earlier deletion",
    [
        FieldEdit(range: CFRange(location: 5, length: 1), replacement: ""),
        FieldEdit(range: CFRange(location: 10, length: 3), replacement: "the"),
    ],
    expect: [(9, 3)]
)

print("\n== which apps may be read at all ==")

func checkPolicy(_ name: String, _ policy: AppPolicy, _ bundleID: String?, expect: Bool) {
    let result = policy.permits(bundleID)
    let ok = result == expect
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { print("        got: \(result)\n   expected: \(expect)") }
}

/// Exclusions only: everything passes but the apps named.
let excludingOnly = AppPolicy(denied: ["com.apple.Terminal"], allowed: [])

checkPolicy("an unnamed app passes", excludingOnly, "com.apple.Safari", expect: true)
checkPolicy("an excluded app does not", excludingOnly, "com.apple.Terminal", expect: false)
checkPolicy("no identifier passes while nothing is included", excludingOnly, nil, expect: true)

/// Naming even one app to include narrows everything else out.
let narrowed = AppPolicy(denied: ["com.apple.Terminal"], allowed: ["com.apple.Mail"])

checkPolicy("an included app passes", narrowed, "com.apple.Mail", expect: true)
checkPolicy("an app that is neither does not", narrowed, "com.apple.Safari", expect: false)
checkPolicy("no identifier does not, once anything is included", narrowed, nil, expect: false)

/// The point of the two-table split: exclusion wins, whatever the other list says.
let contradicting = AppPolicy(denied: ["com.apple.Terminal"], allowed: ["com.apple.Terminal"])

checkPolicy("including an excluded app does not readmit it", contradicting, "com.apple.Terminal", expect: false)
checkPolicy("and does not readmit anything else either", contradicting, "com.apple.Mail", expect: false)

/// A seeded exclusion has to survive an inclusion list drawn up around it.
let seededPlusIncludes = AppPolicy(denied: AppPolicy.defaultDenied, allowed: ["com.apple.dt.Xcode", "com.apple.Mail"])
checkPolicy("a seeded exclusion outranks being included", seededPlusIncludes, "com.apple.dt.Xcode", expect: false)
checkPolicy("while the rest of that list still works", seededPlusIncludes, "com.apple.Mail", expect: true)

/// Every seeded exclusion has to actually be excluded, or the seed is decorative.
let seeded = AppPolicy()
for bundleID in AppPolicy.defaultDenied.sorted() {
    checkPolicy("excluded by default: \(bundleID)", seeded, bundleID, expect: false)
}

/// The reason given has to match, since one is spoken aloud and the other is not.
func checkReason(_ name: String, _ policy: AppPolicy, _ bundleID: String?, expect: AppPolicy.Decision) {
    let result = policy.decision(for: bundleID)
    let ok = result == expect
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { print("        got: \(result)\n   expected: \(expect)") }
}

checkReason("an excluded app reports exclusion", narrowed, "com.apple.Terminal", expect: .excluded)
checkReason("an app left out reports omission", narrowed, "com.apple.Safari", expect: .notIncluded)
checkReason("exclusion is reported ahead of omission", contradicting, "com.apple.Terminal", expect: .excluded)

print("\n== what the history shows of a change ==")

func checkExcerpt(
    _ name: String,
    of text: String,
    highlighting range: CFRange?,
    expect: (String, String, String)
) {
    let result = TextExcerpt.build(from: text, highlighting: range)
    let ok = result.before == expect.0 && result.changed == expect.1 && result.after == expect.2
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok {
        print("        got: \(result.before)|\(result.changed)|\(result.after)")
        print("   expected: \(expect.0)|\(expect.1)|\(expect.2)")
    }
}

checkExcerpt(
    "a short field is shown whole",
    of: "teh cat sat",
    highlighting: CFRange(location: 0, length: 3),
    expect: ("", "teh", " cat sat")
)
checkExcerpt(
    "a change in the middle keeps both sides",
    of: "the cat sat",
    highlighting: CFRange(location: 4, length: 3),
    expect: ("the ", "cat", " sat")
)
/// A pure insertion has nothing to highlight, which the view has to render anyway.
checkExcerpt(
    "an insertion has an empty middle",
    of: "the cat",
    highlighting: CFRange(location: 7, length: 0),
    expect: ("the cat", "", "")
)
/// Nothing to centre on, so the field is clipped from the start instead.
checkExcerpt(
    "no range falls back to the start of the field",
    of: "the cat sat",
    highlighting: nil,
    expect: ("the cat sat", "", "")
)

/// The case that matters: one small fix inside a field far longer than the window.
let long = String(repeating: "a", count: 300) + "teh" + String(repeating: "b", count: 300)
let excerpt = TextExcerpt.build(from: long, highlighting: CFRange(location: 300, length: 3))
let trimmedOK = excerpt.changed == "teh"
    && excerpt.before == "…" + String(repeating: "a", count: TextExcerpt.contextCharacters)
    && excerpt.after == String(repeating: "b", count: TextExcerpt.contextCharacters) + "…"
if !trimmedOK { failures += 1 }
print("\(trimmedOK ? "PASS" : "FAIL") a long field is trimmed to the change")
if !trimmedOK {
    print("        got: \(excerpt.before.count) before, \(excerpt.changed), \(excerpt.after.count) after")
}

/// Emoji and accents must not be cut mid-character by the offset maths.
checkExcerpt(
    "counts characters, not UTF-16 units",
    of: "I 👍 teh cat",
    highlighting: CFRange(location: 5, length: 3),
    expect: ("I 👍 ", "teh", " cat")
)

print("\n== when the whole field may be rewritten ==")

func checkCovers(_ name: String, _ range: CFRange, of text: String, expect: Bool) {
    let result = WriteScope.coversWholeField(range, of: text)
    let ok = result == expect
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { print("        got: \(result)\n   expected: \(expect)") }
}

let field = "the cat sat on the mat"

checkCovers("the whole field may be rewritten", CFRange(location: 0, length: field.utf16.count), of: field, expect: true)
checkCovers("a selection at the start may not", CFRange(location: 0, length: 3), of: field, expect: false)
checkCovers("a selection in the middle may not", CFRange(location: 4, length: 3), of: field, expect: false)
checkCovers("a selection reaching the end may not", CFRange(location: 4, length: field.utf16.count - 4), of: field, expect: false)
checkCovers("an empty field is trivially whole", CFRange(location: 0, length: 0), of: "", expect: true)

/// The case that flattened a Chrome field: a small fix inside a long one.
let longField = String(repeating: "x", count: 825)
checkCovers(
    "28 characters inside 825 may not",
    CFRange(location: 100, length: 28),
    of: longField,
    expect: false
)

/// A range running past the end still counts, since nothing outside it survives anyway.
checkCovers("a range past the end still counts", CFRange(location: 0, length: 9_999), of: field, expect: true)

print("\n== chunks never own the whitespace between them ==")

/// The chunker hands each piece to the model on its own. If a piece carries the
/// space or newline that separates it from the next one, the model replies
/// without it, and the diff reads the loss as ordinary spacing, which is exactly
/// the kind of change the guardrail is built to allow. Two words end up glued
/// together and a paragraph break disappears.
func checkChunks(_ name: String, _ text: String) {
    let ranges = TextChunker.chunks(of: text)

    var covered = ""
    var cursor = text.startIndex
    for range in ranges {
        covered += text[cursor..<range.lowerBound]
        covered += text[range]
        cursor = range.upperBound
    }
    covered += text[cursor...]

    let holdsNewline = ranges.contains { text[$0].contains(where: \.isNewline) }
    let holdsEdge = ranges.contains {
        text[$0].first?.isWhitespace == true || text[$0].last?.isWhitespace == true
    }
    let ok = covered == text && !holdsNewline && !holdsEdge

    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok {
        print("        roundTrip: \(covered == text) newline: \(holdsNewline) edge: \(holdsEdge)")
    }
}

let sentence = "Wir haben das Thema gestern lange besprochen. "
let paragraph = String(repeating: sentence, count: 14)

checkChunks("a line short enough to send whole", "teh cat sat")
checkChunks("two lines", "hallo anna\nwie gehts")
checkChunks("blank lines between", "one\n\n\ntwo")
checkChunks("a leading indent", "    hallo anna")
checkChunks("a trailing newline", "hallo anna\n")
checkChunks("nothing but whitespace", "   \n  \n")
checkChunks("a long paragraph split into several", paragraph)
checkChunks("a long paragraph then a signature", paragraph + "\nViele gruesse, Chris")
checkChunks("a long line with no sentence marks", String(repeating: "wort ", count: 200))
checkChunks("non-BMP characters in a long line", paragraph + " 👍 Schluss.")

print("\n== a full stop is judged by the end of its line ==")

/// Corrections run line by line, so judging "is this the end of a sentence" by
/// the end of the whole field meant that on any message with more than one line
/// every line but the last failed the test. The full stop then fell through to
/// the catch-all punctuation rule, and the setting offered for exactly this
/// question did nothing wherever it mattered.
check("a stop on a middle line, endings off", "hallo anna\nwie gehts", "hallo anna.\nwie gehts",
      allowing: [.capitalisation, .typos, .commas], expect: "hallo anna\nwie gehts")
check("a stop on the last line, endings off", "hallo anna\nwie gehts", "hallo anna\nwie gehts.",
      allowing: [.capitalisation, .typos, .commas], expect: "hallo anna\nwie gehts")
check("a stop on a middle line, endings on", "hallo anna\nwie gehts", "hallo anna.\nwie gehts",
      allowing: [.capitalisation, .sentenceEndings], expect: "hallo anna.\nwie gehts")
check("a stop genuinely mid-line is ordinary punctuation", "hallo anna wie gehts", "hallo. anna wie gehts",
      allowing: [.capitalisation, .typos, .otherPunctuation], expect: "hallo. anna wie gehts")

print("\n== an edit that does two things needs permission for both ==")

checkRules("umlaut and a noun capital", "das ist mein buero", "das ist mein Büro",
           expect: [.umlauts, .nounCapitalisation])
checkRules("umlaut and a comma", "gruesse dich", "grüße, dich", expect: [.umlauts, .commas])
checkRules("umlaut and a joined word", "haus tuer", "Haustür",
           expect: [.umlauts, .spacing, .capitalisation])
checkRules("umlaut alone", "gruesse", "grüße", expect: [.umlauts])

check("an umlaut may not smuggle in a capital", "das ist mein buero", "das ist mein Büro",
      allowing: [.umlauts, .typos, .spacing], expect: "das ist mein buero")
check("an umlaut may not smuggle in a comma", "gruesse dich", "grüße, dich",
      allowing: [.umlauts, .typos, .spacing], expect: "gruesse dich")
check("with both allowed it lands", "das ist mein buero", "das ist mein Büro",
      allowing: [.umlauts, .nounCapitalisation], expect: "das ist mein Büro")

print("\n== punctuation that changes meaning is not punctuation ==")

check("a thousands separator", "Das kostet 1,500 Euro", "Das kostet 1.500 Euro", expect: "Das kostet 1,500 Euro")
check("the other way round", "Das kostet 1.500 Euro", "Das kostet 1,500 Euro", expect: "Das kostet 1.500 Euro")
check("a time", "we meet at 10:30 sharp", "we meet at 10.30 sharp", expect: "we meet at 10:30 sharp")
check("a question turned into a statement", "kommst du morgen?", "kommst du morgen.", expect: "kommst du morgen?")
check("trimming a doubled mark is still allowed", "really?!", "really?", expect: "really?")
check("a comma next to a word is untouched by this", "hello , world", "hello, world", expect: "hello, world")

print("\n== protected text also stops insertions ==")

check("a comma inside a code span", "run `foo bar` now", "run `foo, bar` now", expect: "run `foo bar` now")
check("a stop inside a url", "see https://a.example/b now", "see https://a.example/b. now",
      expect: "see https://a.example/b now")

/// Straying into a URL is not the same as rewriting the user's prose, so it must
/// not out-vote the corrections that came with it.
check("handles do not cost the typo fix", "hey @Anna und @Bob, teh deploy ist durch",
      "hey @anna und @bob, the deploy ist durch",
      expect: "hey @Anna und @Bob, the deploy ist durch")

print("\n== a line break opens a sentence ==")

checkRules("first word of a new line", "hi anna\nhope you are well", "hi anna\nHope you are well",
           expect: [.capitalisation])
check("english capitalises after a line break", "hi anna\nhope you are well", "Hi anna\nHope you are well",
      allowing: [.capitalisation, .typos], expect: "Hi anna\nHope you are well")

print("\n== english capitalises names ==")

/// English does not capitalise nouns as a class, so the rule was left out. But
/// the classifier judges a capital by position, not by knowing the word, so
/// every mid-sentence capital lands under it and names could never be fixed.
let englishRules: Set<CorrectionRule> = [.spacing, .capitalisation, .nounCapitalisation,
                                         .commas, .sentenceEndings, .otherPunctuation,
                                         .apostrophes, .typos]

check("a name mid-sentence", "i work at google", "I work at Google",
      allowing: englishRules, expect: "I work at Google")
check("a weekday", "see you on tuesday", "See you on Tuesday",
      allowing: englishRules, expect: "See you on Tuesday")
check("still refused when the rule is off", "i work at google", "I work at Google",
      allowing: englishRules.subtracting([.nounCapitalisation]), expect: "I work at google")
check("it is still not a licence to rewrite", "i work at google", "I work at Alphabet",
      allowing: englishRules, expect: "I work at google")

print("\n== a typo fix that also changes a capital needs both ==")

checkRules("typo carrying a sentence capital", "teh cat sat", "The cat sat",
           expect: [.typos, .capitalisation])
checkRules("typo carrying a mid-sentence capital", "i met teh anna", "i met Teh anna",
           expect: [.nounCapitalisation])
checkRules("typo with no capital in it", "teh cat sat", "the cat sat", expect: [.typos])

check("capitalisation off refuses the capital and the fix with it", "teh cat sat", "The cat sat",
      allowing: [.typos, .spacing, .commas], expect: "teh cat sat")
check("with both allowed it lands", "teh cat sat", "The cat sat",
      allowing: [.typos, .capitalisation], expect: "The cat sat")
check("a lower-case typo fix is untouched by this", "teh cat sat", "the cat sat",
      allowing: [.typos], expect: "the cat sat")

print("\n== markup is not punctuation ==")

/// A model that shows its work by bolding what it changed. Seen in Slack: a
/// German line came back with every changed letter wrapped in `**`, and since
/// `*` is punctuation to Unicode, each one read as a capital plus a
/// punctuation change and all four landed in the user's message.
check("markdown bold around a changed letter", "hab die evals gefixt",
      "Hab die **E**vals **G**efixt", expect: "hab die evals gefixt")
check("markdown bold around a whole word", "das war gut", "das war **gut**",
      expect: "das war gut")
check("backticks the user did not write", "run the script", "run the `script`",
      expect: "run the script")
check("italics", "that was fast", "that was _fast_", expect: "that was fast")
check("a heading marker", "next steps", "## next steps", expect: "next steps")
check("a bullet the model added", "buy milk", "- buy milk", expect: "buy milk")
check("bolding a word blocks that word and nothing else", "teh cat sat", "**The** cat sat.",
      expect: "teh cat sat.")

checkRules("bolding is not a correction", "evals", "**E**vals", expect: [])

/// The marks writing actually uses still work, in both forms, and a mark the
/// user wrote themselves may still be moved around.
check("curly quotes still land", "he said hi", "he said \u{201C}hi\u{201D}", expect: "he said \u{201C}hi\u{201D}")
check("german quotes still land", "er sagte hallo", "er sagte \u{201E}hallo\u{201C}",
      expect: "er sagte \u{201E}hallo\u{201C}")
check("an em dash still lands", "wait what", "wait \u{2014} what", expect: "wait \u{2014} what")
check("a hyphen still lands", "well known issue", "well-known issue", expect: "well-known issue")
check("an ellipsis still lands", "i wondered", "i wondered\u{2026}", expect: "i wondered\u{2026}")
check("an asterisk the user wrote survives being moved past",
      "*note* this ,here", "*note* this, here", expect: "*note* this, here")

print("\n== protected text is hidden from the model, then put back ==")

/// Hiding a link is only safe if it comes back character for character, and
/// only useful if the model still sees a sentence.
func checkMask(_ name: String, _ text: String, reply: (String) -> String, expect: String?) {
    let masked = MaskedText.mask(text, protecting: ProtectedSpans.find(in: text))
    let got = masked.restore(reply(masked.text))
    let ok = got == expect
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL") \(name)")
    if !ok { print("        got: \(got ?? "nil")\n   expected: \(expect ?? "nil")") }
}

/// The model returns the marker untouched, which is the ordinary case.
checkMask("a link is hidden and restored", "schau mal hier github.com/a/b",
          reply: { $0.replacingOccurrences(of: "schau", with: "Schau") },
          expect: "Schau mal hier github.com/a/b")
checkMask("several spans keep their own places", "ping @anna about `run.sh` at github.com/a/b",
          reply: { $0 }, expect: "ping @anna about `run.sh` at github.com/a/b")
checkMask("text with nothing to hide is untouched", "hallo welt",
          reply: { $0 + "." }, expect: "hallo welt.")

/// The failure paths, which are the whole reason this is not a plain substitution.
checkMask("a dropped marker abandons the chunk", "schau mal hier github.com/a/b",
          reply: { $0.replacingOccurrences(of: MaskedText.marker(0), with: "") }, expect: nil)
checkMask("a duplicated marker abandons the chunk", "schau mal hier github.com/a/b",
          reply: { $0 + " " + MaskedText.marker(0) }, expect: nil)
checkMask("a rewritten marker abandons the chunk", "schau mal hier github.com/a/b",
          reply: { $0.replacingOccurrences(of: MaskedText.marker(0), with: "[link]") }, expect: nil)

/// The link is the whole point: whatever the model does to the marker's
/// surroundings, the link itself cannot be edited, because it was never shown.
checkMask("the model cannot damage what it never saw", "mail an chris@example.com bitte",
          reply: { $0.replacingOccurrences(of: "mail", with: "Mail") },
          expect: "Mail an chris@example.com bitte")

/// Overlapping spans are the normal case, not an edge case: a link is matched
/// by its own pattern and by the data detector both.
checkMask("overlapping spans do not nest", "siehe https://github.com/a/b hier",
          reply: { $0 }, expect: "siehe https://github.com/a/b hier")

/// A marker sitting where a sentence starts comes back capitalised, which
/// names the same span and must not cost the chunk.
checkMask("a marker that came back capitalised still restores", "github.com/a/b is the one",
          reply: { $0.replacingOccurrences(of: MaskedText.marker(0), with: MaskedText.marker(0).capitalized) },
          expect: "github.com/a/b is the one")

/// `ZQX1` opens `ZQX10`, so a message with eleven hidden spans has to restore
/// the long markers first or the short ones match inside them.
checkMask("eleven spans do not collide",
          "a " + (0..<11).map { "@user\($0)" }.joined(separator: " b ") + " c",
          reply: { $0 },
          expect: "a " + (0..<11).map { "@user\($0)" }.joined(separator: " b ") + " c")

print("\n== a line break is not spacing ==")

/// Seen from a model asked to correct a chat message: it returned the tail of
/// the line one word per line, and every break passed as a spacing fix.
check("a word pushed onto its own line", "i will take a look tomorrow",
      "i will\ntake\na\nlook\ntomorrow", expect: "i will take a look tomorrow")
check("a line break inserted before a link", "see this github.com/a/b",
      "see this\ngithub.com/a/b", expect: "see this github.com/a/b")
check("two lines joined into one", "first line\nsecond line",
      "first line second line", expect: "first line\nsecond line")
check("a double space still collapses", "hello  world", "hello world", expect: "hello world")
check("a space before a comma still goes", "a , b", "a, b", expect: "a, b")
check("a line break the model left alone is no obstacle", "hallo anna\n\nvielen dank",
      "Hallo Anna\n\nVielen Dank", allowing: Set(CorrectionRule.allCases),
      expect: "Hallo Anna\n\nVielen Dank")

print("\n== umlauts are restored, never spelled away ==")

/// Seen from the model on a correctly written German sign-off: it returned
/// `Viele Gruesse` for `Viele Gruesse` with the eszett spelled out and the noun
/// lowercased, and folding made the two compare equal so it passed as a fix.
check("an eszett is not spelled back out", "Viele Gr\u{FC}\u{DF}e", "Viele gr\u{FC}sse",
      expect: "Viele Gr\u{FC}\u{DF}e")
check("an umlaut is not spelled back out", "die \u{C4}nderungen", "die Aenderungen",
      expect: "die \u{C4}nderungen")
check("restoring an eszett still lands", "viele gruesse", "viele Gr\u{FC}\u{DF}e",
      expect: "viele Gr\u{FC}\u{DF}e")
check("restoring an umlaut still lands", "die aenderungen", "die \u{C4}nderungen",
      expect: "die \u{C4}nderungen")
check("an umlaut left alone is untouched", "die \u{C4}nderungen sind drausen",
      "die \u{C4}nderungen sind drau\u{DF}en", expect: "die \u{C4}nderungen sind drau\u{DF}en")

print("")

print("\n== a bug report carries the correction, and nothing else leaves ==")

func report(before: String, after: String = "x") -> IssueReport {
    IssueReport(
        before: before,
        after: after,
        appName: "Slack",
        bundleID: "com.tinyspeck.slackmacgap",
        editCount: 2,
        backend: "Apple on-device",
        appVersion: "1.0 (4)",
        systemVersion: "Version 26.6.2 (Build 25G83)"
    )
}

func checkReport(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    if !condition { failures += 1 }
    print("\(condition ? "PASS" : "FAIL") \(name)")
    if !condition, !detail().isEmpty { print("        got: \(detail())") }
}

/// A message about code carries backticks, and a fence of three would end the
/// block early, spilling the rest of the report into prose and taking the
/// details table with it.
let fenced = IssueReport.fenced("run ```make test``` first")
checkReport("a fence outlasts the backticks inside it", fenced.hasPrefix("````"), fenced)
checkReport(
    "the text survives fencing unchanged",
    fenced.contains("run ```make test``` first")
)
checkReport("an ordinary message gets a plain fence", IssueReport.fenced("hello").hasPrefix("```\n"))

/// The form has to be readable, and a very long field would fill it with text
/// the reader has to scroll past to reach the question.
let overlongReport = String(repeating: "a", count: IssueReport.textLimit + 500)
checkReport("a long field is cut", IssueReport.clipped(overlongReport).count < overlongReport.count)
checkReport("and says where it was cut", IssueReport.clipped(overlongReport).hasSuffix("[…]"))
checkReport("a short field is left alone", IssueReport.clipped("hello") == "hello")

/// Nothing is sent from the app, so everything has to survive the trip through a
/// URL: the text is the reproduction, and a mangled one is worth nothing.
let simple = report(before: "hallo anna, danke fuer die rueckmeldung", after: "Hallo Anna, danke für die Rückmeldung")
checkReport("the form is prefilled", simple.url != nil)
checkReport(
    "the report names the model, so the reader knows what answered",
    simple.body.contains("Apple on-device")
)
checkReport("and the app it happened in", simple.body.contains("com.tinyspeck.slackmacgap"))
checkReport("and both versions of the text", simple.body.contains("hallo anna") && simple.body.contains("Hallo Anna"))
checkReport("the title quotes the text so the list is readable", simple.title.contains("hallo anna"))

/// A URL the browser cuts in half loses the second half of the report silently,
/// which is worse than not opening one at all.
/// Clipping the text is what keeps a report inside a link, so the two limits
/// have to be checked against each other rather than separately: a full-length
/// field on both sides still has to fit once every space has cost three
/// characters to encode.
let huge = report(
    before: String(repeating: "wort ", count: 4_000),
    after: String(repeating: "Wort ", count: 4_000)
)
checkReport("a report of any length still fits in a link", huge.url != nil)
checkReport("and the body is bounded", huge.body.count < 2 * IssueReport.textLimit + 600)

/// The text is clipped, and nothing else is. A field long enough to overflow
/// anyway must lose the link rather than the second half of the report.
let overflowing = IssueReport(
    before: "hello",
    after: "Hello",
    appName: String(repeating: "app ", count: 2_000),
    bundleID: nil,
    editCount: 1,
    backend: "Apple on-device",
    appVersion: "1.0 (4)",
    systemVersion: "26.6.2"
)
checkReport("too long for a link is refused rather than truncated", overflowing.url == nil)
checkReport("and the body survives for the clipboard", overflowing.body.contains("hello"))

/// Percent-encoding is the part that goes wrong quietly: a naive join produces a
/// URL that opens with everything after the first umlaut missing.
let tricky = report(before: "Grüße & Co #1 + 2 = drei?", after: "Grüße & Co #1 + 2 = drei")
if let url = tricky.url?.absoluteString {
    checkReport("an ampersand cannot start a new field", !url.contains("&Co"))
    checkReport("a hash cannot start a fragment", !url.contains("#1"))
    checkReport("a plus is not read as a space", url.contains("%2B"))
} else {
    checkReport("a short report with punctuation still fits in a link", false)
}

let newlines = report(before: "erste zeile\nzweite zeile")
checkReport(
    "a line break survives as a line break",
    newlines.url?.absoluteString.contains("%0A") == true
)


print("\n== a correction gives up rather than hang ==")

func checkDeadline(_ name: String, _ condition: Bool) {
    if !condition { failures += 1 }
    print("\(condition ? "PASS" : "FAIL") \(name)")
}

let start = ContinuousClock().now
let deadline = CorrectionDeadline(budget: .seconds(20), now: start)

checkDeadline("a fresh pass has its whole budget", deadline.remaining(at: start) == .seconds(20))
checkDeadline("and has not expired", !deadline.hasExpired(at: start))
checkDeadline("a used-up pass has expired", deadline.hasExpired(at: start + .seconds(20)))

/// The budget must bound the requests, not the other way round. A request
/// started with two seconds left may not run for six, or every limit past the
/// last one is decided by the request rather than by the pass.
checkDeadline(
    "a request early in the pass gets the request limit",
    deadline.allowance(at: start) == CorrectionDeadline.perRequest
)
checkDeadline(
    "a request near the end gets only what is left",
    deadline.allowance(at: start + .seconds(18)) == .seconds(2)
)
checkDeadline(
    "a request after the end gets nothing",
    deadline.allowance(at: start + .seconds(25)) == .zero
)
checkDeadline(
    "time never runs backwards",
    deadline.remaining(at: start + .seconds(40)) == .zero
)

/// The point of the limit is that a stuck request stops costing time, whether
/// or not it notices it has been cancelled.
let quick = await answered(within: .seconds(5)) { "answered" }
checkDeadline("a request inside its allowance answers", quick == "answered")

/// Deliberately a request with no suspension point to cancel at. Sleeping here
/// instead proves nothing, because a sleep ends the moment it is cancelled: the
/// first version of this passed that test and still held the pass open for the
/// full three seconds when measured against a request that does not notice.
let began = ContinuousClock().now
let slow = await answered(within: .milliseconds(200)) {
    let until = Date().addingTimeInterval(3)
    var spin = 0.0
    while Date() < until { spin += 1 }

    return "much too late (\(spin > 0))"
}
let waited = ContinuousClock().now - began
checkDeadline("a request past its allowance gives up", slow == nil)
checkDeadline("and does not keep the pass waiting for it", waited < .seconds(1))

let none = await answered(within: .zero) { "should not run" }
checkDeadline("no allowance means no request", none == nil)

if failures == 0 {
    print("all passed")
} else {
    print("\(failures) FAILURES")
    exit(1)
}
SWIFT

swift "$SOURCE"
SWIFT_STATUS=$?

# The description the model is shown exists twice: once in the app, once in the
# eval's own copy of the same shape. They are not one string, because a @Guide
# description has to be a literal in the type, so nothing but a check keeps them
# equal. When they drifted, a sweep silently measured the old wording and
# reported it as the new one, which is the worst way for a measurement to fail:
# it produced plausible numbers for a comparison that was not being made.
description_in() {
    python3 -c '
import sys

source = open(sys.argv[1], encoding="utf-8").read()
shape = source.split("struct CorrectedText {", 1)[1].split("let text", 1)[0]
print(" ".join(shape.replace("\\\n", " ").split()))
' "$1"
}

APP_DESCRIPTION=$(description_in Spellbee/Engine/FoundationModelsCorrector.swift)
EVAL_DESCRIPTION=$(description_in Eval/Sources/spellbee-eval/EvalBackend.swift)

if [ "$APP_DESCRIPTION" = "$EVAL_DESCRIPTION" ]; then
    echo "PASS the eval measures the description the app ships"
else
    echo "FAIL the eval measures the description the app ships"
    echo "        app : $APP_DESCRIPTION"
    echo "        eval: $EVAL_DESCRIPTION"
    exit 1
fi

exit $SWIFT_STATUS
