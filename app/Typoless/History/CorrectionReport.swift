import Foundation

/**
 A report about one correction, written as an issue on the public tracker.

 A correction that goes wrong is the one thing about this app that cannot be
 reproduced from a description. The model is deterministic, so the exact text
 that went in is the whole reproduction, and it is also the thing the user is
 least likely to retype accurately. Everything needed is already in the history
 entry; this turns it into a report.

 **Nothing is sent from here.** It is a prefilled link, described in
 `IssueTracker`, and the issue exists only once the user presses Submit in their
 own browser.

 The text sits in fenced blocks rather than in prose, so a message that is
 itself about code or formatting arrives exactly as it was written.
 */
struct CorrectionReport {
    /** How much of each version of the text the report carries before it is cut. */
    static let textLimit = 1_500

    let before: String
    let after: String
    /** Where the correction happened, named for a person rather than by identifier. */
    let appName: String?
    let bundleID: String?
    let editCount: Int
    let backend: String
    let environment: ReportEnvironment

    var title: String {
        let excerpt = Self.firstLine(of: before, limit: 60)

        return excerpt.isEmpty ? "Wrong correction" : "Wrong correction: \(excerpt)"
    }

    var body: String {
        """
        ### What is wrong with it? What should it have done instead?



        Delete anything below that you would rather not make public.

        ### Before
        \(IssueTracker.fenced(Self.clipped(before)))

        ### After
        \(IssueTracker.fenced(Self.clipped(after)))

        ### Details
        App: \(appDescription)
        Changes applied: \(editCount)
        Model: \(backend)
        \(environment.lines.joined(separator: "\n"))
        """
    }

    private var appDescription: String {
        switch (appName, bundleID) {
        case let (name?, id?): return "\(name) (\(id))"
        case let (name?, nil): return name
        case let (nil, id?): return id
        case (nil, nil): return "unknown"
        }
    }

    /**
     The prefilled form, or nil where the text is too long to travel in a link.

     The caller falls back to the clipboard rather than opening a form with a
     body silently cut in half.
     */
    var url: URL? {
        IssueTracker.newIssue(title: title, body: body)
    }

    /** Where the user goes when the report has to travel by clipboard. */
    var blankIssueURL: URL? {
        IssueTracker.newIssue(title: title, body: nil)
    }

    /** Keeps a very long field from filling the report, marking where it was cut. */
    static func clipped(_ text: String) -> String {
        guard text.count > textLimit else { return text }

        return String(text.prefix(textLimit)) + "\n[…]"
    }

    private static func firstLine(of text: String, limit: Int) -> String {
        let line = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""

        guard line.count > limit else { return line }

        return String(line.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
