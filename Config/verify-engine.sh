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
    Spellbee/Engine/EditGuardrail.swift \
    Spellbee/Engine/ProtectedSpans.swift \
    Spellbee/Engine/ModelReplyCleaner.swift \
    Spellbee/Accessibility/FieldEdit.swift \
    > "$SOURCE"

cat >> "$SOURCE" <<'SWIFT'

var failures = 0

/// Runs the text the user wrote and the text the model returned through the
/// guardrail, and checks what the field would end up containing.
func check(_ name: String, _ original: String, _ modelOutput: String, expect: String) {
    let protected = ProtectedSpans.find(in: original)
    let verdict = EditGuardrail.filter(TextDiff.edits(from: original, to: modelOutput), protectedBy: protected)
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

print("\n== known gap, pinned so it cannot change unnoticed ==")

// A word whose ending changes within two edits reads as a typo to the distance
// rule, so "hause" becomes "häuser" and the sentence now says something else.
// This was never blocked on its merits: before the spelling distance ignored
// case, the same change was refused when a model capitalised it and accepted
// when it did not. Closing it needs a rule about word endings, not a budget.
check("word ending changed within budget", "wir fahren nach hause", "wir fahren nach häuser", expect: "wir fahren nach häuser")

print("\n== whole chunk refused ==")
check("rephrase", "the meeting is at 5", "The meeting has been scheduled for 5", expect: "the meeting is at 5")
check("translation", "wir gehen ins kino", "we are going to the cinema", expect: "wir gehen ins kino")
check("mostly rewritten", "can you send it over when your done", "Please forward it once you have finished.", expect: "can you send it over when your done")
check("model answered instead", "what is the capital of france", "The capital of France is Paris.", expect: "what is the capital of france")

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

print("")
if failures == 0 {
    print("all passed")
} else {
    print("\(failures) FAILURES")
    exit(1)
}
SWIFT

swift "$SOURCE"
