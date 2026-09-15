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
        guard let revisions = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory.appending(path: "snapshots"),
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        /**
         A part-finished fetch leaves whole shards behind as ordinary files, and
         these models come in several. One `.safetensors` therefore proves
         nothing: it reported a third of Gemma as fully downloaded, which made
         the app refuse to resume the download and then hang on the first
         correction while the rest arrived with no progress shown at all.
         */
        let blobs = (try? FileManager.default.contentsOfDirectory(
            atPath: cacheDirectory.appending(path: "blobs").path
        )) ?? []

        guard !blobs.contains(where: { $0.hasSuffix(".incomplete") }) else { return false }

        return revisions.contains { revision in
            let files = (try? FileManager.default.contentsOfDirectory(atPath: revision.path)) ?? []

            return files.contains { $0.hasSuffix(".safetensors") } && files.contains("config.json")
        }
    }

    /** The Hugging Face repository these weights come from. */
    var repositoryID: String { configuration.name }

    /** Where the hub keeps this model, whether or not anything is there yet. */
    var cacheDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache/huggingface/hub")
            .appending(path: "models--" + repositoryID.replacingOccurrences(of: "/", with: "--"))
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

/**
 One pickable model, named in a single value.

 A backend plus a separate local model says the same thing in two places, which
 leaves "Apple's model is in use, and also Gemma is the selected one"
 representable and forces every reader to combine them. This does not.
 */
enum ModelChoice: Equatable, Hashable, Sendable {
    case appleOnDevice
    case local(LocalModel)

    var displayName: String {
        switch self {
        case .appleOnDevice: return CorrectorBackend.appleOnDevice.displayName
        case .local(let model): return model.displayName
        }
    }

    /**
     One string, so a choice can be written to user defaults.

     Deliberately not the backend's raw value for the Apple case and the model's
     for the other: those two vocabularies could collide as they grow, and the
     stored value has to survive a model being removed from the app, which is
     what `init?` is for.
     */
    var storageKey: String {
        switch self {
        case .appleOnDevice: return "apple"
        case .local(let model): return "local:" + model.rawValue
        }
    }

    init?(storageKey: String) {
        if storageKey == "apple" {
            self = .appleOnDevice
            return
        }

        guard
            storageKey.hasPrefix("local:"),
            let model = LocalModel(rawValue: String(storageKey.dropFirst("local:".count)))
        else { return nil }

        self = .local(model)
    }
}
