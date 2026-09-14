import Foundation
import FoundationModels
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/**
 A model that can be asked for a corrected chunk.

 Deliberately narrower than `Corrector`: everything above this line, the
 chunking, the diff and the guardrail, is shared by every backend, so the only
 thing a backend does is turn a prompt into a reply. That is what makes a
 comparison between two of them mean anything.
 */
protocol EvalBackend: Sendable {
    var id: String { get }
    var displayName: String { get }

    /** Loads whatever the backend needs before it is timed. */
    func prepare() async throws

    /** Nil when the model declines or fails, which leaves the chunk untouched. */
    func reply(instructions: String, prompt: String, freeTextSuffix: String) async -> String?

    /** Frees the weights, which are the largest thing this process ever holds. */
    func release() async
}

extension EvalBackend {
    func release() async {}
}

/** Every backend the app can be configured with, in a fixed order. */
enum Backends {
    static func all() -> [any EvalBackend] {
        SchemaMode.allCases.map { AppleBackend(schema: $0) } + LocalModel.allCases.map(MLXBackend.init)
    }

    static func named(_ id: String) -> (any EvalBackend)? {
        all().first { $0.id == id }
    }
}

/**
 Apple's on-device model, asked for a structured value.

 `CorrectedText` repeats the shape the app declares privately in
 `FoundationModelsCorrector`. It is a schema rather than a prompt, so the thing
 under test is still the real one; keeping a second copy here avoids widening
 the app's own declaration for the benefit of a tool.
 */
/**
 How the reply is shaped, which is a second prompt hiding as a type.

 Guided generation constrains the model to a schema instead of free text, and
 the schema's `@Guide` description goes into the model's context. That
 description is 143 characters of instruction that no prompt variant can reach,
 restating the allowed changes and adding a rule the tuned wording does not
 carry at all. With the wording now down to 267 characters, a third of what the
 model reads about its task lives there, so it is worth measuring rather than
 assuming.
 */
enum SchemaMode: String, Sendable, CaseIterable {
    /** Guided generation with the description the app ships. */
    case described
    /** Guided generation with no description at all, leaving only the wording. */
    case bare
    /** No schema. The reply is free text and the preamble sits in the instructions. */
    case freeInstructions
    /** No schema. The preamble sits at the end of the user turn instead. */
    case freePrompt

    var suffix: String {
        switch self {
        case .described: return ""
        case .bare: return "-bare"
        case .freeInstructions: return "-free"
        case .freePrompt: return "-free-suffix"
        }
    }

    var isGuided: Bool { self == .described || self == .bare }
}

/**
 Apple's on-device model.

 `CorrectedText` repeats the shape the app declares privately in
 `FoundationModelsCorrector`, so the thing under test is the real one. Note that
 its description is not merely a schema: the model reads it, so it is part of
 the prompt whether or not it is written like one. `PlainText` is the same
 shape with that description removed, which is what makes the two comparable.
 */
struct AppleBackend: EvalBackend {
    let schema: SchemaMode

    init(schema: SchemaMode = .described) { self.schema = schema }

    var id: String { CorrectorBackend.appleOnDevice.rawValue + schema.suffix }
    var displayName: String { CorrectorBackend.appleOnDevice.displayName + schema.suffix }

    private var model: SystemLanguageModel {
        SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }

    func prepare() async throws {
        guard model.isAvailable else { throw EvalError.backendUnavailable(displayName) }
    }

    func reply(instructions: String, prompt: String, freeTextSuffix: String) async -> String? {
        let preamble = "\n\nReturn only the corrected text, nothing else."
        let session = LanguageModelSession(
            model: model,
            instructions: schema == .freeInstructions ? instructions + preamble : instructions
        )
        let asked = schema == .freePrompt ? prompt + freeTextSuffix : prompt
        let options = GenerationOptions(sampling: .greedy)

        do {
            switch schema {
            case .described:
                return try await session.respond(to: asked, generating: CorrectedText.self, options: options).content.text
            case .bare:
                return try await session.respond(to: asked, generating: PlainText.self, options: options).content.text
            case .freeInstructions, .freePrompt:
                /**
                 Free text arrives with whatever packaging the model felt like
                 adding, which the guided path never had to deal with. Cleaned
                 exactly as the MLX backend cleans it, or the comparison would
                 be between two shapes rather than two schemas.
                 */
                let raw = try await session.respond(to: asked, options: options).content
                return ModelReplyCleaner.clean(raw, of: prompt)
            }
        } catch {
            return nil
        }
    }
}

@Generable
private struct CorrectedText {
    @Guide(
        description: """
        The text with only spelling, punctuation, capitalisation and spacing \
        corrected. Every original word must still be present, in the same order.
        """
    )
    let text: String
}

/** The same shape with the description taken away, so the schema says nothing. */
@Generable
private struct PlainText {
    let text: String
}

/**
 A downloaded model running through MLX.

 An actor because the container is loaded once and reused across every case in a
 run, which is also what the app does within a session.
 */
actor MLXBackend: EvalBackend {
    private let model: LocalModel
    private var container: ModelContainer?

    init(_ model: LocalModel) {
        self.model = model
    }

    nonisolated var id: String { model.rawValue }
    nonisolated var displayName: String { model.displayName }

    func prepare() async throws {
        try Self.requireMetalLibrary()
        _ = try await loadedContainer()
    }

    /**
     Fails early when MLX's kernels were never compiled.

     Xcode compiles the `.metal` files inside a package; SwiftPM does not, so an
     executable built with `swift build` gets as far as the first array and then
     dies inside C++ with a message about a metallib. Saying so before a
     multi-gigabyte load is friendlier than saying it after.
     */
    private static func requireMetalLibrary() throws {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()

        guard !FileManager.default.fileExists(
            atPath: executable.appendingPathComponent("mlx.metallib").path
        ) else {
            return
        }

        throw EvalError.metalLibraryMissing(executable.path)
    }

    func release() {
        container = nil
    }

    func reply(instructions: String, prompt: String, freeTextSuffix: String) async -> String? {
        guard let container = try? await loadedContainer() else { return nil }

        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(temperature: 0)
        )

        var request = prompt + freeTextSuffix
        if model.usesThinkingBlocks {
            request += " /no_think"
        }

        do {
            return ModelReplyCleaner.clean(try await session.respond(to: request))
        } catch {
            return nil
        }
    }

    private func loadedContainer() async throws -> ModelContainer {
        if let container { return container }

        let configuration = model.configuration
        let loaded = try await #huggingFaceLoadModelContainer(configuration: configuration) { _ in }
        container = loaded

        return loaded
    }
}

enum EvalError: Error, CustomStringConvertible {
    case backendUnavailable(String)
    case metalLibraryMissing(String)
    case unknownArgument(String)
    case missingDatasets

    var description: String {
        switch self {
        case .backendUnavailable(let name):
            return "\(name) is not available on this machine"
        case .metalLibraryMissing(let directory):
            return "no mlx.metallib in \(directory); run ./build-metallib.sh"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        case .missingDatasets:
            return "Could not find a Datasets directory"
        }
    }
}
