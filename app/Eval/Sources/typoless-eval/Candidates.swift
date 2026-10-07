import Foundation
import MLXLLM
import MLXLMCommon

/**
 A downloaded model this harness can measure.

 Deliberately not `LocalModel`, which is the list the app offers in its menu.
 The two were the same list, and that made the question "should we ship this
 model" impossible to answer honestly: measuring a candidate meant first
 offering it to users, with its weights, its download size and its name in the
 settings window, on the strength of a guess. The order has to be the other way
 round, so the harness keeps its own list and the app's is a subset of it.

 A candidate that wins is promoted by adding it to `LocalModel`, where the
 download size and the display name have to be filled in properly. A candidate
 that loses leaves a measurement behind and nothing else.
 */
struct Candidate: Sendable {
    let id: String
    let displayName: String
    let configuration: ModelConfiguration
    /**
     Whether the model narrates its reasoning first, which the prompt then asks
     it to skip. Most of the generation time for a task this small.
     */
    let usesThinkingBlocks: Bool

    init(
        id: String,
        displayName: String,
        configuration: ModelConfiguration,
        usesThinkingBlocks: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.configuration = configuration
        self.usesThinkingBlocks = usesThinkingBlocks
    }

    /**
     What the app ships, read from the app's own list rather than repeated here.

     A sweep with no `--model` measures these and only these, so the daily
     question, "did this change move the numbers", never waits for gigabytes of
     a model nobody has decided to ship.
     */
    static let shipping: [Candidate] = LocalModel.allCases.map {
        Candidate(
            id: $0.rawValue,
            displayName: $0.displayName,
            configuration: $0.configuration,
            usesThinkingBlocks: $0.usesThinkingBlocks
        )
    }

    /**
     Models under consideration, measured only when named with `--model`.

     Each one is here for a reason that can be written in a line, since a model
     with no argument for it is a download and a sweep spent on nothing.
     */
    static let considered: [Candidate] = [
        /** Built for on-device, and the smallest thing worth asking a sentence of. */
        Candidate(
            id: "lfm2_1_2b",
            displayName: "LFM2 1.2B",
            configuration: LLMRegistry.lfm2_1_2b_4bit
        ),
    ]

    /**
     Gemma 4 E2B is not here any more because it won and was promoted.

     It is the first candidate this list was built for, and it beat the E4B the
     app was shipping on every number: 80 per cent exact match in English
     against 43, 71 against 66 in German, a fifth of the changes nobody asked
     for, and 1.5 GB less to download. The larger model finds slightly more and
     will not stop there, which exact match notices and recall does not.
     */

    /**
     Helium 1 2B is not here, and the reason is worth keeping.

     Kyutai trained it for European languages, which is this app's whole list,
     so it was the most interesting thing on the shelf. It cannot be loaded:
     `swift-transformers` dies on its tokenizer with "BPETokenizer requires
     merges", and the only MLX conversion in existence is the preview
     repository MLX's own registry points at, with 26 downloads. Converting it
     by hand and repairing the tokenizer is a day's work for a model nobody has
     measured, so this waits for a conversion somebody else makes.

     It also cost a lesson about this harness: it is only in MLX 3.32.3, the
     package was bumped to reach it, and that bump has been taken back. A
     candidate that needs a newer MLX has to prove itself worth the bump first,
     not after.
     */
    static let all: [Candidate] = shipping + considered
}
