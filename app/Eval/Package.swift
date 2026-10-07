// swift-tools-version: 6.2
import PackageDescription

/**
 Evaluation harness for the correction prompt.

 The engine sources under `Sources/typoless-eval/Engine` are symlinks into
 `Typoless/`, not copies, so the harness measures the prompt, the diff and the
 guardrail the app actually ships. SwiftPM refuses a target path outside the
 package root, which is why the link sits inside the target rather than the
 target pointing outward.

 Everything lives in one module because the engine types are internal and adding
 `public` to them for the benefit of a test tool would change the app's own
 sources.

 Package versions match `Typoless.xcodeproj`; `Package.resolved` is copied from
 the project so both build against identical revisions.

 The one exception is a model the app cannot reach yet. MLX's registry is where
 a new model first appears, so measuring one means the harness leads the app by
 a version until the model is either adopted, which brings the app with it, or
 dropped. A sweep in that state still compares models fairly, since every model
 in it runs on the same MLX, and it is not a baseline for anything else.
 */
let package = Package(
    name: "typoless-eval",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.31.4")),
        .package(url: "https://github.com/huggingface/swift-huggingface", .upToNextMinor(from: "0.9.0")),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3"),
    ],
    targets: [
        .executableTarget(
            name: "typoless-eval",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
