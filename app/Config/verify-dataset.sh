#!/bin/bash
#
# Checks that every expected output in the eval datasets is actually reachable.
#
# A case whose expected text the guardrail would refuse can never be passed, no
# matter how good the model is. Scoring against it measures nothing and quietly
# caps the achievable score. This asks the opposite question from a model run:
# given a *perfect* answer, would the app apply it?
#
#     ./Config/verify-dataset.sh
#
# Needs no model and no network. Run it after editing a dataset.

set -euo pipefail
cd "$(dirname "$0")/.."

SCRATCH=$(mktemp -d)
SOURCE="$SCRATCH/verify.swift"
CASES="$SCRATCH/cases.json"

python3 - "$CASES" <<'PYTHON'
import json, sys
out = []
for language in ("en", "de"):
    data = json.load(open(f"Eval/Datasets/{language}.json"))
    for case in data["cases"]:
        answers = [case["expected"]] + case.get("alternatives", [])
        for index, answer in enumerate(answers):
            out.append({
                "id": case["id"] if index == 0 else f"{case['id']} (alternative {index})",
                "language": language,
                "input": case["input"],
                "expected": answer,
            })
json.dump(out, open(sys.argv[1], "w"), ensure_ascii=False)
PYTHON

# The guardrail reads a language's rule set, and `AppSettings` names the model
# a language prefers without the scorer ever needing one. Both types are
# stand-ins: the real ones bring the MLX packages, which a single swiftc call
# cannot build.
cat > "$SOURCE" <<'SWIFT'
enum LocalModel: String, Equatable, Hashable, Sendable { case placeholder }
enum ModelChoice: Equatable, Hashable, Sendable {
    case appleOnDevice
    case local(LocalModel)
}
SWIFT

cat \
    Typoless/Support/Log.swift \
    Typoless/Engine/TextDiff.swift \
    Typoless/Engine/CorrectionRule.swift \
    Typoless/Engine/EditGuardrail.swift \
    Typoless/Engine/WordList.swift \
    Typoless/Engine/ProtectedSpans.swift \
    Typoless/Engine/AppSettings.swift \
    Typoless/Engine/CorrectionLanguage.swift \
    >> "$SOURCE"

cat >> "$SOURCE" <<'SWIFT'

struct Item: Codable {
    let id: String
    let language: String
    let input: String
    let expected: String
}

let items = try JSONDecoder().decode(
    [Item].self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)

func shown(_ text: String) -> String {
    text.replacingOccurrences(of: "\n", with: "\\n")
}

var unreachable = 0

for item in items {
    let language: CorrectionLanguage = item.language == "de" ? .german : .english
    let verdict = EditGuardrail.filter(
        TextDiff.edits(from: item.input, to: item.expected),
        in: item.input,
        allowing: language.applicableRules,
        protectedBy: ProtectedSpans.find(in: item.input),
        language: language
    )
    let result = verdict.isTrustworthy ? TextDiff.apply(verdict.accepted, to: item.input) : item.input

    guard result != item.expected else { continue }

    unreachable += 1
    print("UNREACHABLE \(item.id)   accepted=\(verdict.accepted.count) refused=\(verdict.rejectedCount) trusted=\(verdict.isTrustworthy)")
    print("     input   : \(shown(item.input))")
    print("     expected: \(shown(item.expected))")
    print("     best the guardrail allows: \(shown(result))")
}

print("")
if unreachable == 0 {
    print("all \(items.count) cases reachable")
} else {
    print("\(unreachable) of \(items.count) cases unreachable even from a perfect model")
    exit(1)
}
SWIFT

swift "$SOURCE" "$CASES"
