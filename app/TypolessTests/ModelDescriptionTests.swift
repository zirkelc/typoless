import Foundation
import Testing

/**
 The eval measures the description the app ships.

 The description the model is shown exists twice: once in the app, once in the
 eval's own copy of the same shape. They are not one string, because a guide
 description has to be a literal in the type, so nothing but a check keeps them
 equal. When they drifted, a sweep silently measured the old wording and
 reported it as the new one, which is the worst way for a measurement to fail:
 it produced plausible numbers for a comparison that was not being made.

 This reads both source files from the checkout, which works because the test
 host is not sandboxed.
 */
struct ModelDescriptionTests {
    /** The app folder, found from this file's own place in the checkout. */
    private static let appFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /**
     The first `CorrectedText` shape in a source file, up to its property, with
     line continuations and runs of whitespace collapsed to single spaces.
     */
    private static func description(in relativePath: String) throws -> String {
        let url = appFolder.appendingPathComponent(relativePath)
        let source = try String(contentsOf: url, encoding: .utf8)
        let opening = try #require(source.range(of: "struct CorrectedText {"))
        let rest = source[opening.upperBound...]
        let shape = rest.range(of: "let text").map { rest[..<$0.lowerBound] } ?? rest

        return shape
            .replacingOccurrences(of: "\\\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    @Test func `the eval measures the description the app ships`() throws {
        // Arrange
        let appPath = "Typoless/Engine/FoundationModelsCorrector.swift"
        let evalPath = "Eval/Sources/typoless-eval/EvalBackend.swift"

        // Act
        let app = try Self.description(in: appPath)
        let eval = try Self.description(in: evalPath)

        // Assert
        #expect(!app.isEmpty)
        #expect(app == eval)
    }
}
