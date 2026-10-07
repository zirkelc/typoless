#if DEBUG
import Foundation

/**
 Writes every correction pass to disk, whole, including the text.

 **This is the one place in the app that keeps what somebody wrote, and it is
 compiled out of every release build.** The history window holds the same text
 in memory and lets it die with the process, on purpose. A file does not, which
 is exactly why it is useful here and why it may never ship: weeks of real use
 is the only source of the three things the datasets cannot invent, which are
 the texts people actually type, the replies this model actually gives them, and
 the refusals nobody thought to write a case for.

 What it is for, in order:

 - **Dataset cases.** A pass that went wrong is a case with its input already
   written, and the reply beside it says what the expected output has to beat.
 - **Prompt work.** `Eval/` measures wordings against cases somebody wrote by
   hand. A month of this is a sample of the real distribution, which is the
   thing the hand-written sets keep being wrong about.
 - **Rules.** A change the guardrail refused, over and over, with the same
   shape, is a rule waiting to be named.

 One line of JSON per pass, one file per day, appended. A crash loses at most
 the pass that was running, and the file can be read with `jq` while the app is
 still running, which a single document could not offer.
 */
final class PassRecorder: @unchecked Sendable {
    static let shared = PassRecorder()

    /** One request to the model, whether or not anything came of it. */
    struct Chunk: Codable {
        let source: String
        let language: String
        /** Nil where the model refused, failed or ran out of time. */
        let reply: String?
        let seconds: Double
    }

    /** One change the pass offered, applied or refused, as the history shows it. */
    struct Note: Codable {
        let before: String
        let after: String?
        /**
         The refusal as the enum describes itself, nil where the change was
         made. Taken from the value rather than written out again here, so a
         new reason appears in the recordings on the day it is added and
         nothing has to be kept in step.
         */
        let refusal: String?
    }

    struct Record: Codable {
        let date: Date
        /** Which app the text was in, which is most of why a pass behaves oddly. */
        let app: String?
        let version: String
        /** The models that answered, named as the menu names them. */
        let models: [String]
        /** Every language the pass read, in the order it first read them. */
        let languages: [String]
        let before: String
        let after: String
        let editCount: Int
        let didChange: Bool
        /** How the text was written back, nil where nothing was written. */
        let strategy: String?
        let seconds: Double
        let chunks: [Chunk]
        let notes: [Note]
    }

    /**
     Guarded by a lock rather than actor isolation, because the two halves of a
     pass are recorded from different places: the chunks from whichever actor
     the backend runs on, the result from the main actor. A lock lets both say
     so without either having to await the other.
     */
    private let lock = NSLock()
    private var chunks: [Chunk] = []
    private var started = Date()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        /** Stable key order, so two days of recordings diff against each other. */
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        return encoder
    }()

    /** Where a month of recordings collects. Shown in the debug menu. */
    static var directory: URL { shared.directory }

    private static var defaultDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Typoless/passes")
    }

    let directory: URL

    /**
     - Parameter directory: Where to write. Given a temporary one by the tests,
       which would otherwise append to the recordings of whoever ran them.
     */
    init(directory: URL = PassRecorder.defaultDirectory) {
        self.directory = directory
    }

    /** Called as a pass starts, which is also what discards an abandoned one. */
    func begin() {
        lock.withLock {
            chunks = []
            started = Date()
        }
    }

    func add(source: String, language: CorrectionLanguage, reply: String?, took: Duration) {
        let seconds = Double(took.components.seconds) + Double(took.components.attoseconds) * 1e-18

        lock.withLock {
            chunks.append(Chunk(source: source, language: language.rawValue, reply: reply, seconds: seconds))
        }
    }

    /**
     Closes the pass and writes it.

     Called from the one place that records history, so a pass reaches the file
     under exactly the conditions it reaches the history window: every pass,
     including the ones that changed nothing, which are the interesting ones.
     */
    func finish(
        before: String,
        after: String,
        bundleID: String?,
        models: [String],
        outcome: CorrectionOutcome,
        editCount: Int,
        strategy: String?
    ) {
        let (chunks, started) = lock.withLock { (self.chunks, self.started) }

        let record = Record(
            date: started,
            app: bundleID,
            version: Self.version,
            models: models,
            languages: outcome.languages.map(\.rawValue),
            before: before,
            after: after,
            editCount: editCount,
            didChange: before != after,
            strategy: strategy,
            seconds: Date().timeIntervalSince(started),
            chunks: chunks,
            notes: outcome.notes.map {
                Note(
                    before: $0.before,
                    after: $0.after,
                    refusal: $0.refusal.map { String(describing: $0) }
                )
            }
        )

        write(record)
    }

    private func write(_ record: Record) {
        guard var line = try? Self.encoder.encode(record) else {
            Log.app.error("Could not encode a pass recording")
            return
        }

        line.append(0x0A)

        let file = directory.appending(path: "\(Self.today).jsonl")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            /**
             Appended through a handle rather than read, joined and written
             back, so the file stays one pass away from complete at any moment
             and a day of recordings is never held in memory twice.
             */
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }

                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: file, options: .atomic)
            }
        } catch {
            Log.app.error("Could not write a pass recording: \(String(describing: error), privacy: .public)")
        }
    }

    private static var today: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        return formatter.string(from: Date())
    }

    /** Kept with every pass, since a recording outlives the build that made it. */
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        return "\(short) (\(build))"
    }
}
#endif
