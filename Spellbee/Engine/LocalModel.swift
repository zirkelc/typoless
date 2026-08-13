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

    /**
     Whether the weights are already on disk.

     Asked of the cache rather than remembered in settings, so it stays true
     when someone clears the cache behind our back, and so a model downloaded
     by another MLX app counts as present.
     */
    var isDownloaded: Bool {
        let hub = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache/huggingface/hub")
            .appending(path: "models--" + repositoryID.replacingOccurrences(of: "/", with: "--"))
            .appending(path: "snapshots")

        guard let revisions = try? FileManager.default.contentsOfDirectory(
            at: hub,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        /** A directory can exist with the download half done, so look for weights. */
        return revisions.contains { revision in
            let files = (try? FileManager.default.contentsOfDirectory(atPath: revision.path)) ?? []
            return files.contains { $0.hasSuffix(".safetensors") }
        }
    }

    /** The Hugging Face repository these weights come from. */
    var repositoryID: String { configuration.name }

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
