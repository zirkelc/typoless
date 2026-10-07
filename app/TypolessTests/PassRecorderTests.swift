import Foundation
import Testing
@testable import Typoless

/**
 The recordings are the only copy of what really happened.

 A pass that is wrong is reported weeks after it ran, by which time the field,
 the history window and the process are all gone. If the file is missing a
 field, holds the wrong text or quietly overwrites yesterday, nobody finds out
 until the day they need it, which is the day it is too late to fix.
 */
struct PassRecorderTests {
    private static func recorder() -> (PassRecorder, URL) {
        let directory = URL.temporaryDirectory.appending(path: "passes-\(UUID().uuidString)")

        return (PassRecorder(directory: directory), directory)
    }

    private static func lines(in directory: URL) throws -> [PassRecorder.Record] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try files
            .flatMap { try String(contentsOf: $0, encoding: .utf8).split(separator: "\n") }
            .map { try decoder.decode(PassRecorder.Record.self, from: Data($0.utf8)) }
    }

    @Test
    func `a pass is written whole, with its chunks and its reasons`() throws {
        // Arrange
        let (recorder, directory) = Self.recorder()
        var outcome = CorrectionOutcome()
        outcome.add(language: .english)
        outcome.add(CorrectionNote(before: "teh", after: "the"))
        outcome.add(CorrectionNote(before: "384 KB", after: nil, refusal: .modelDeclined))

        // Act
        recorder.begin()
        recorder.add(source: "teh meeting", language: .english, reply: "the meeting", took: .milliseconds(400))
        recorder.finish(
            before: "teh meeting",
            after: "the meeting",
            bundleID: "com.apple.mail",
            models: ["Apple on-device"],
            outcome: outcome,
            editCount: 1,
            strategy: "edits"
        )

        // Assert
        let records = try Self.lines(in: directory)
        #expect(records.count == 1)

        let record = try #require(records.first)
        #expect(record.before == "teh meeting")
        #expect(record.after == "the meeting")
        #expect(record.app == "com.apple.mail")
        #expect(record.editCount == 1)
        #expect(record.didChange)
        #expect(record.strategy == "edits")
        #expect(record.languages == ["english"])
        #expect(record.chunks.count == 1)
        #expect(record.chunks.first?.reply == "the meeting")
        #expect(record.notes.count == 2)
        #expect(record.notes.first?.refusal == nil)
        #expect(record.notes.last?.refusal == "modelDeclined")
    }

    /** The case that matters most: nothing changed, and the file says why. */
    @Test
    func `a pass that changed nothing is written too`() throws {
        // Arrange
        let (recorder, directory) = Self.recorder()
        var outcome = CorrectionOutcome()
        outcome.add(CorrectionNote(before: "Should we remove teh projects?", after: nil, refusal: .modelDeclined))

        // Act
        recorder.begin()
        recorder.add(source: "Should we remove teh projects?", language: .english, reply: nil, took: .seconds(1))
        recorder.finish(
            before: "Should we remove teh projects?",
            after: "Should we remove teh projects?",
            bundleID: nil,
            models: ["Apple on-device"],
            outcome: outcome,
            editCount: 0,
            strategy: nil
        )

        // Assert
        let record = try #require(try Self.lines(in: directory).first)
        #expect(record.didChange == false)
        #expect(record.strategy == nil)
        #expect(record.chunks.first?.reply == nil)
        #expect(record.notes.first?.refusal == "modelDeclined")
    }

    /** A day is many passes, and the second must not take the first one's place. */
    @Test
    func `passes are appended, one line each`() throws {
        // Arrange
        let (recorder, directory) = Self.recorder()

        // Act
        for text in ["one", "two", "three"] {
            recorder.begin()
            recorder.finish(
                before: text,
                after: text,
                bundleID: nil,
                models: [],
                outcome: CorrectionOutcome(),
                editCount: 0,
                strategy: nil
            )
        }

        // Assert
        let records = try Self.lines(in: directory)
        #expect(records.count == 3)
        #expect(records.map(\.before) == ["one", "two", "three"])
    }

    /** Beginning a pass drops whatever the abandoned one had gathered. */
    @Test
    func `a new pass does not inherit the chunks of the last`() throws {
        // Arrange
        let (recorder, directory) = Self.recorder()

        // Act
        recorder.begin()
        recorder.add(source: "abandoned", language: .english, reply: nil, took: .zero)
        recorder.begin()
        recorder.add(source: "kept", language: .english, reply: "kept", took: .zero)
        recorder.finish(
            before: "kept",
            after: "kept",
            bundleID: nil,
            models: [],
            outcome: CorrectionOutcome(),
            editCount: 0,
            strategy: nil
        )

        // Assert
        let record = try #require(try Self.lines(in: directory).first)
        #expect(record.chunks.count == 1)
        #expect(record.chunks.first?.source == "kept")
    }
}
