import Foundation
import MLXLLM
import MLXLMCommon

/** A downloadable model that can stand in for Apple's on-device one. */
enum LocalModel: String, CaseIterable, Sendable {
    case qwen35_2b
    case gemma4_e4b

    var displayName: String {
        switch self {
        case .qwen35_2b: return "Qwen3.5 2B"
        case .gemma4_e4b: return "Gemma 4 E4B"
        }
    }

    /**
     Download size, so the menu can say what it is about to cost.

     Measured from the repositories rather than estimated from the parameter
     count, which is how Gemma came to be advertised at nearly half its real
     size. Worth re-checking if a model is repointed at a different checkpoint.
     */
    var approximateSize: String {
        switch self {
        case .qwen35_2b: return "1.6 GB"
        case .gemma4_e4b: return "4.8 GB"
        }
    }

    var configuration: ModelConfiguration {
        switch self {
        case .qwen35_2b: return LLMRegistry.qwen3_5_2b_4bit
        case .gemma4_e4b: return LLMRegistry.gemma4_e4b_it_4bit
        }
    }

    /**
     Whether the model narrates its reasoning before answering.

     Qwen emits a `<think>` block by default. It is harmless once removed, but
     it is most of the generation time for a task this small, which is why the
     prompt asks it to skip.
     */
    var usesThinkingBlocks: Bool {
        switch self {
        case .qwen35_2b: return true
        case .gemma4_e4b: return false
        }
    }
}

/** Which model does the correcting. */
enum CorrectorBackend: String, CaseIterable, Sendable {
    case appleOnDevice
    case local

    var displayName: String {
        switch self {
        case .appleOnDevice: return "Apple on-device"
        case .local: return "Downloaded model"
        }
    }
}
