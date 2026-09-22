import Foundation
import Testing
@testable import Typoless

/** A correction gives up rather than hang. */
struct CorrectionDeadlineTests {
    private let start = ContinuousClock().now

    private var deadline: CorrectionDeadline {
        CorrectionDeadline(budget: .seconds(20), now: start)
    }

    @Test func `a fresh pass has its whole budget`() {
        // Arrange
        let deadline = deadline

        // Act
        let remaining = deadline.remaining(at: start)

        // Assert
        #expect(remaining == .seconds(20))
    }

    @Test func `and has not expired`() {
        // Arrange
        let deadline = deadline

        // Act
        let expired = deadline.hasExpired(at: start)

        // Assert
        #expect(!expired)
    }

    @Test func `a used-up pass has expired`() {
        // Arrange
        let deadline = deadline

        // Act
        let expired = deadline.hasExpired(at: start + .seconds(20))

        // Assert
        #expect(expired)
    }

    /**
     The budget must bound the requests, not the other way round. A request
     started with two seconds left may not run for six, or every limit past the
     last one is decided by the request rather than by the pass.
     */
    @Test func `a request early in the pass gets the request limit`() {
        // Arrange
        let deadline = deadline

        // Act
        let allowance = deadline.allowance(at: start)

        // Assert
        #expect(allowance == CorrectionDeadline.perRequest)
    }

    @Test func `a request near the end gets only what is left`() {
        // Arrange
        let deadline = deadline

        // Act
        let allowance = deadline.allowance(at: start + .seconds(18))

        // Assert
        #expect(allowance == .seconds(2))
    }

    @Test func `a request after the end gets nothing`() {
        // Arrange
        let deadline = deadline

        // Act
        let allowance = deadline.allowance(at: start + .seconds(25))

        // Assert
        #expect(allowance == .zero)
    }

    @Test func `time never runs backwards`() {
        // Arrange
        let deadline = deadline

        // Act
        let remaining = deadline.remaining(at: start + .seconds(40))

        // Assert
        #expect(remaining == .zero)
    }

    /**
     The point of the limit is that a stuck request stops costing time, whether
     or not it notices it has been cancelled.
     */
    @Test func `a request inside its allowance answers`() async {
        // Arrange
        let allowance: Duration = .seconds(5)

        // Act
        let quick = await answered(within: allowance) { "answered" }

        // Assert
        #expect(quick == "answered")
    }

    /**
     Deliberately a request with no suspension point to cancel at. Sleeping here
     instead proves nothing, because a sleep ends the moment it is cancelled: the
     first version of this passed that test and still held the pass open for the
     full three seconds when measured against a request that does not notice.

     Both checks share one run, because the second one measures the first.
     */
    @Test func `a request past its allowance gives up, and does not keep the pass waiting for it`() async {
        // Arrange
        let began = ContinuousClock().now

        // Act
        let slow = await answered(within: .milliseconds(200)) {
            let until = Date().addingTimeInterval(3)
            var spin = 0.0
            while Date() < until { spin += 1 }

            return "much too late (\(spin > 0))"
        }
        let waited = ContinuousClock().now - began

        // Assert
        #expect(slow == nil)
        #expect(waited < .seconds(1))
    }

    @Test func `no allowance means no request`() async {
        // Arrange
        let allowance: Duration = .zero

        // Act
        let none = await answered(within: allowance) { "should not run" }

        // Assert
        #expect(none == nil)
    }
}
