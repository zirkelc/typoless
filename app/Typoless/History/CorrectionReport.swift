import Foundation

/**
 A bug report about one correction, written as an e-mail.

 A correction that goes wrong is the one thing about this app that cannot be
 reproduced from a description. The model is deterministic, so the exact text
 that went in is the whole reproduction, and it is also the thing the user is
 least likely to retype accurately. Everything needed is already in the history
 entry; this turns it into a message.

 **Nothing is sent from here.** The report is a prefilled `mailto:` link that
 opens a draft in the user's mail app, so they read the whole thing, edit or
 delete whatever they do not want to share, and press Send themselves.

 E-mail rather than a public issue tracker, because the report carries the
 user's own writing. On a tracker, anyone could read it, which would be a
 strange thing to build into an app whose promise is that text does not leave
 the Mac. A mail goes to one address, and only when the user sends it.
 */
struct CorrectionReport {
    /**
     Where reports go.

     A constant rather than a setting: a report about a correction is only
     useful to the people who make the app that made it.
     */
    static let address = "feedback@typoless.app"

    /**
     What a mail app will reliably accept in a link.

     Some mail apps cut a long `mailto:` link without an error, so anything
     longer takes the clipboard route instead.
     */
    static let urlLengthLimit = 6_000

    /** How much of each version of the text the draft carries before it is cut. */
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

    var subject: String {
        let excerpt = Self.firstLine(of: before, limit: 60)

        return excerpt.isEmpty ? "Wrong correction" : "Wrong correction: \(excerpt)"
    }

    /**
     Plain text, since that is what every mail app shows the same way.

     The two versions of the text sit between marker lines rather than in any
     markup, so a message that is itself about code or formatting arrives
     exactly as it was.
     */
    var body: String {
        """
        What is wrong with it? What should it have done instead?



        Delete anything below that you would rather not send.

        ----- Before -----
        \(Self.clipped(before))

        ----- After -----
        \(Self.clipped(after))

        ----- Details -----
        App: \(appDescription)
        Changes applied: \(editCount)
        Model: \(backend)
        Typoless: \(appVersion)
        macOS: \(systemVersion)
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
     The draft, prefilled, or nil where the text is too long to travel in a link.

     The caller falls back to the clipboard rather than opening a draft with a
     body silently cut in half.
     */
    var url: URL? {
        let address = Self.mailto(subject: subject, body: body)

        guard address.count <= Self.urlLengthLimit else { return nil }

        return URL(string: address)
    }

    /** Where the user goes when the report has to travel by clipboard. */
    var blankDraftURL: URL? {
        URL(string: Self.mailto(subject: subject, body: nil))
    }

    /**
     Builds the link by hand.

     A `mailto:` body has to use CRLF line breaks, and everything outside the
     unreserved set is encoded. `URLComponents` would leave `+` alone, which
     some mail apps turn back into a space, so "1 + 2" would arrive as "1   2"
     in the one part of the report that has to be exact.
     */
    private static func mailto(subject: String, body: String?) -> String {
        var fields = ["subject=" + encoded(subject)]

        if let body {
            let crlf = body
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: "\r\n")
            fields.append("body=" + encoded(crlf))
        }

        return "mailto:\(address)?" + fields.joined(separator: "&")
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

    /** Keeps a very long field from filling the draft, marking where it was cut. */
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
