import Foundation
import Testing
@testable import Typoless

/**
 A report carries the correction, and nothing else leaves.

 The text is the reproduction, so everything has to survive the trip through the
 link exactly, and nothing may be cut without the user seeing it.
 */
struct CorrectionReportTests {
    private func report(before: String, after: String = "x") -> CorrectionReport {
        CorrectionReport(
            before: before,
            after: after,
            appName: "Slack",
            bundleID: "com.tinyspeck.slackmacgap",
            editCount: 2,
            backend: "Apple on-device",
            environment: ReportEnvironment(appVersion: "1.0 (4)", systemVersion: "Version 26.6.2 (Build 25G83)")
        )
    }

    @Test func `the report opens a new issue on the tracker`() throws {
        // Arrange
        let simple = report(before: "hallo anna", after: "Hallo Anna")

        // Act
        let url = try #require(simple.url)

        // Assert
        #expect(url.scheme == "https")
        #expect(url.host == "github.com")
        #expect(url.path == "/\(IssueTracker.repository)/issues/new")
    }

    @Test func `the body names the model, the app and both versions`() {
        // Arrange
        let simple = report(
            before: "hallo anna, danke fuer die rueckmeldung",
            after: "Hallo Anna, danke für die Rückmeldung"
        )

        // Act
        let body = simple.body

        // Assert
        #expect(body.contains("Apple on-device"))
        #expect(body.contains("com.tinyspeck.slackmacgap"))
        #expect(body.contains("hallo anna, danke fuer die rueckmeldung"))
        #expect(body.contains("Hallo Anna, danke für die Rückmeldung"))
        #expect(body.contains("Typoless: 1.0 (4)"))
        #expect(simple.title == "Wrong correction: hallo anna, danke fuer die rueckmeldung")
    }

    @Test func `text survives encoding exactly`() throws {
        // Arrange
        let before = "Grüße & Co #1 + 2 = drei?\nzweite Zeile"
        let tricky = report(before: before, after: "Grüße & Co #1 + 2 = drei")

        // Act
        let url = try #require(tricky.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let body = components.queryItems?.first { $0.name == "body" }?.value
        let address = url.absoluteString

        // Assert
        #expect(!address.contains("&Co"))
        #expect(!address.contains("#1"))
        #expect(address.contains("%2B"))
        #expect(!address.contains("ü"))
        #expect(body?.contains(before) == true)
    }

    /**
     A report is very often about markup, so the block that carries the text has
     to be longer than anything inside it.
     */
    @Test func `a fence is always longer than the backticks it encloses`() {
        // Arrange
        let plain = "hello"
        let code = "use `map` here"
        let block = "```swift\nlet x = 1\n```"

        // Act
        let fencedPlain = IssueTracker.fenced(plain)
        let fencedCode = IssueTracker.fenced(code)
        let fencedBlock = IssueTracker.fenced(block)

        // Assert
        #expect(fencedPlain.hasPrefix("```text\n"))
        #expect(fencedCode.hasPrefix("```text\n"))
        #expect(fencedBlock.hasPrefix("````text\n"))
        #expect(fencedBlock.hasSuffix("\n````"))
        #expect(fencedBlock.contains(block))
    }

    @Test func `a long field is cut, and says where`() {
        // Arrange
        let overlong = String(repeating: "a", count: CorrectionReport.textLimit + 500)

        // Act
        let clipped = CorrectionReport.clipped(overlong)

        // Assert
        #expect(clipped.count == CorrectionReport.textLimit + 4)
        #expect(clipped.hasSuffix("\n[…]"))
        #expect(CorrectionReport.clipped("hello") == "hello")
    }

    /**
     Clipping is what keeps a report inside a link, so the two limits are
     checked together: a full-length field on both sides still has to fit once
     every space has cost three characters to encode.
     */
    @Test func `a report of any length still fits in a link`() {
        // Arrange
        let huge = report(
            before: String(repeating: "wort ", count: 4_000),
            after: String(repeating: "Wort ", count: 4_000)
        )

        // Act
        let url = huge.url

        // Assert
        #expect(url != nil)
    }

    /** Only the text is clipped. Anything else long enough must lose the link, not the report. */
    @Test func `too long for a link falls back rather than truncating`() {
        // Arrange
        let overflowing = CorrectionReport(
            before: "hello",
            after: "Hello",
            appName: String(repeating: "app ", count: 2_000),
            bundleID: nil,
            editCount: 1,
            backend: "Apple on-device",
            environment: ReportEnvironment(appVersion: "1.0 (4)", systemVersion: "26.6.2")
        )

        // Act
        let url = overflowing.url
        let blank = overflowing.blankIssueURL?.absoluteString

        // Assert
        #expect(url == nil)
        #expect(overflowing.body.contains("hello"))
        #expect(blank?.contains("body=") == false)
    }
}
