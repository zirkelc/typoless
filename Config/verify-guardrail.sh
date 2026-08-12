#!/bin/bash
#
# Checks that the guardrail applies real corrections and refuses rewrites.
#
# The rules it covers are the app's central promise, and they are pure
# functions of two strings, so they are worth checking without a running app or
# a model. Run from the repo root:
#
#     ./Config/verify-guardrail.sh
#
# This concatenates the engine sources with the cases below and runs them as a
# script. It stands in for a real test target, which the project does not have
# yet.

set -euo pipefail
cd "$(dirname "$0")/.."

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
SOURCE="$SCRATCH/verify.swift"

cat \
    Spellbee/Support/Log.swift \
    Spellbee/Engine/TextDiff.swift \
    Spellbee/Engine/EditGuardrail.swift \
    Spellbee/Engine/ProtectedSpans.swift \
    Spellbee/Engine/ModelReplyCleaner.swift \
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

print("\n== rewriting refused, wording preserved ==")
check("word inserted", "hello world", "hello beautiful world", expect: "hello world")
check("word deleted", "i am very tired", "I am tired", expect: "I am very tired")
check("synonym swap", "that is good", "That is excellent", expect: "That is good")
check("meaning change", "the meeting is at 5", "The meeting was at 5", expect: "The meeting is at 5")
check("umlaut fold is not a licence", "wir fahren nach hause", "Wir fahren nach Häuser", expect: "Wir fahren nach hause")

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

print("")
if failures == 0 {
    print("all passed")
} else {
    print("\(failures) FAILURES")
    exit(1)
}
SWIFT

swift "$SOURCE"
