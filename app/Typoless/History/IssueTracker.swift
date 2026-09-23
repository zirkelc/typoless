import Foundation

/**
 The public issue tracker, and how a prefilled issue is addressed.

 **Nothing is sent from here.** Every link opens GitHub's new-issue form with
 the fields already filled in. The user reads the whole thing in the browser,
 edits or deletes whatever they do not want to share, and presses Submit
 themselves. A link that is never opened posts nothing, and a form that is
 abandoned posts nothing.

 A public tracker rather than the e-mail address this replaces, which means a
 report about a correction carries the user's own writing into a page anyone can
 read. That is a real change and the app says so before the browser opens. What
 it buys is that a report has one home: the person who wrote it can follow it,
 anyone hitting the same thing can say so, and the answer is in the same place
 as the question.
 */
enum IssueTracker {
    /**
     A constant rather than a setting. A report about this app is only useful to
     the people who make it.
     */
    static let repository = "zirkelc/typoless"

    /**
     What GitHub will accept in a link.

     A very long URL comes back as an error page rather than a form, so anything
     longer takes the clipboard route and opens an empty form instead.
     */
    static let urlLengthLimit = 6_000

    static var issuesURL: URL? {
        URL(string: "https://github.com/\(repository)/issues")
    }

    /**
     A prefilled new-issue form, or nil where the body is too long for a link.

     - Parameter body: Nil opens the form with only a title, which is what the
       caller falls back to when the body travels on the clipboard.
     */
    static func newIssue(title: String, body: String?) -> URL? {
        var fields = ["title=" + encoded(title)]

        if let body {
            fields.append("body=" + encoded(body))
        }

        let address = "https://github.com/\(repository)/issues/new?" + fields.joined(separator: "&")

        guard address.count <= urlLengthLimit else { return nil }

        return URL(string: address)
    }

    /**
     A block that arrives exactly as it was written.

     The tracker renders Markdown, and a report is very often *about* markup: a
     message full of backticks, asterisks or hashes is exactly the kind of text
     a correction goes wrong on. The fence is made longer than the longest run
     of backticks inside the text, which is the rule Markdown itself uses, so
     there is no text this can fail to enclose.
     */
    static func fenced(_ text: String) -> String {
        var longest = 0
        var run = 0

        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }

        let fence = String(repeating: "`", count: max(3, longest + 1))

        return "\(fence)text\n\(text)\n\(fence)"
    }

    /**
     The unreserved set, spelled out. `CharacterSet.alphanumerics` would also
     let "ü" through unencoded, since it counts every letter in Unicode.
     */
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}

/** What every report says about the machine it came from. */
struct ReportEnvironment {
    let appVersion: String
    let systemVersion: String

    static var current: ReportEnvironment {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        return ReportEnvironment(
            appVersion: "\(short) (\(build))",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    var lines: [String] {
        ["Typoless: \(appVersion)", "macOS: \(systemVersion)"]
    }
}

/**
 A report that carries no correction: something is wrong, or missing, and the
 user is starting from nothing.

 Opened from the menu rather than from a history entry, so there is no text to
 offer and none is asked for. Only the two version lines are filled in, since
 they are what every report needs and what nobody remembers.
 */
struct ProblemReport {
    let model: String
    let environment: ReportEnvironment

    var title: String { "" }

    var body: String {
        """
        ### What happened?



        ### What did you expect instead?



        ### Details
        Model: \(model)
        \(environment.lines.joined(separator: "\n"))
        """
    }

    var url: URL? {
        IssueTracker.newIssue(title: title, body: body)
    }
}
