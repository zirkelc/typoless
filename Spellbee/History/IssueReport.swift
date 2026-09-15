import Foundation

/**
 A bug report about one correction, written as a GitHub issue.

 A correction that goes wrong is the one thing about this app that cannot be
 reproduced from a description. The model is deterministic, so the exact text
 that went in is the whole reproduction, and it is also the thing the user is
 least likely to retype accurately into a web form. Everything needed is already
 in the history entry; this turns it into an issue.

 **Nothing is sent from here.** The report is a prefilled URL that opens
 GitHub's new-issue form in the browser, so the user reads the whole thing, edits
 or deletes whatever they do not want to publish, and presses the button
 themselves. An app that can post someone's private writing to a public tracker
 without them seeing it first would be a strange thing to build into an app whose
 promise is that their text does not leave the Mac. This is the one place it
 does, and it leaves with the user's hand on it.
 */
struct IssueReport {
    /**
     Where reports go.

     A constant rather than a setting: an issue about a correction is only useful
     in the tracker of the app that made it.
     */
    static let repository = "zirkelc/spellbee"

    /**
     What a browser will carry.

     Servers and browsers both stop accepting a URL somewhere above this, and the
     failure is silent truncation of the body rather than an error, so anything
     longer takes the clipboard route instead.
     */
    static let urlLengthLimit = 6_000

    /** How much of each version of the text the form carries before it is cut. */
    static let textLimit = 1_500

    let before: String
    let after: String
    /** Where the correction happened, named for a person rather than by identifier. */
    let appName: String?
    let bundleID: String?
    let editCount: Int
    let backend: String
    let appVersion: String
    let systemVersion: String

    var title: String {
        let excerpt = Self.firstLine(of: before, limit: 60)

        return excerpt.isEmpty ? "Wrong correction" : "Wrong correction: \(excerpt)"
    }

    var body: String {
        """
        ### What is wrong with it

        <!-- What should it have done instead? Delete anything below you would \
        rather not publish. -->

        ### Before

        \(Self.fenced(Self.clipped(before)))

        ### After

        \(Self.fenced(Self.clipped(after)))

        ### Details

        | | |
        |---|---|
        | App | \(appDescription) |
        | Changes applied | \(editCount) |
        | Model | \(backend) |
        | Spellbee | \(appVersion) |
        | macOS | \(systemVersion) |
        """
    }

    private var appDescription: String {
        switch (appName, bundleID) {
        case let (name?, id?): return "\(name) (`\(id)`)"
        case let (name?, nil): return name
        case let (nil, id?): return "`\(id)`"
        case (nil, nil): return "unknown"
        }
    }

    /**
     The form, prefilled, or nil where the text is too long to travel in a URL.

     The caller falls back to the clipboard rather than opening a form with a
     body silently cut in half.
     */
    var url: URL? {
        let query = [
            "title=" + Self.encoded(title),
            "body=" + Self.encoded(body),
            "labels=" + Self.encoded("wrong correction"),
        ].joined(separator: "&")

        let address = "https://github.com/\(Self.repository)/issues/new?" + query

        guard address.count <= Self.urlLengthLimit else { return nil }

        return URL(string: address)
    }

    /**
     Percent-encodes everything a query string does not reserve.

     `URLComponents` is the obvious tool and is wrong here. It leaves `+`
     alone, which is legal in a query and which a form-encoded reader, such as
     the one behind this page, turns back into a space. "1 + 2" would arrive as
     "1   2", quietly, in the one part of the report that has to be exact,
     because it is the text the correction was made to.
     */
    private static func encoded(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        ) ?? ""
    }

    /** Where the user goes when the report has to travel by clipboard. */
    var blankFormURL: URL? {
        URL(string: "https://github.com/\(Self.repository)/issues/new")
    }

    /**
     Wraps text in a fence longer than any run of backticks inside it.

     A correction is often about code or a chat message, and a message
     containing a fence of its own would otherwise end the block early and turn
     the rest of the report into prose, taking the details table with it.
     */
    static func fenced(_ text: String) -> String {
        var longest = 0
        var run = 0

        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }

        let fence = String(repeating: "`", count: max(3, longest + 1))

        return "\(fence)\n\(text)\n\(fence)"
    }

    /** Keeps a very long field from filling the form, marking where it was cut. */
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
