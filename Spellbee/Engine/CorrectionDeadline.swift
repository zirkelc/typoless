import Foundation
import Synchronization

/**
 How long a whole correction may take before it gives up.

 A pass is not one request. A field is several chunks, each chunk may be asked
 twice when a placeholder does not survive, and each of those may be asked again
 in English when the model declines, so one invocation can be four requests
 deep before anything is written. Nothing bounded that, and the overlay sits on
 the user's live text field for as long as it runs.

 Measured over 168 cases: the median is 0.37s and the 95th percentile is 1.5s,
 and then there is **nothing at all between 1.5s and 48s**. The slow cases are
 not slow, they are stuck, usually a decline the model takes half a minute to
 arrive at. Because the distribution has that gap in it, every limit between 3
 and 20 seconds cuts exactly the same six cases of 168, so the numbers below are
 chosen for what a person will sit through rather than to buy back a case.

 Two limits, because one cannot do both jobs. The per-request limit ends a
 single stuck request quickly. The budget stops a long field from spending that
 limit again and again, chunk after chunk, and reaching the same place slowly.

 Giving up leaves the text exactly as the user wrote it, which is what every
 other failure here does.
 */
struct CorrectionDeadline: Sendable {
    /**
     The longest a single request may run.

     Four times the 95th percentile. Below the gap in the distribution, so it
     ends a stuck request without reaching any request that was going to answer.
     */
    static let perRequest: Duration = .seconds(6)

    /**
     The longest a whole pass may run.

     Enough for a long field of ordinary chunks, since those cost about a second
     each, and short enough that a user watching an overlay is not abandoned to
     it. A pass that runs out stops asking and keeps whatever already landed.
     */
    static let perPass: Duration = .seconds(20)

    private let expiry: ContinuousClock.Instant

    init(budget: Duration = CorrectionDeadline.perPass, now: ContinuousClock.Instant = ContinuousClock().now) {
        expiry = now + budget
    }

    func remaining(at now: ContinuousClock.Instant = ContinuousClock().now) -> Duration {
        let left = expiry - now

        return left > .zero ? left : .zero
    }

    func hasExpired(at now: ContinuousClock.Instant = ContinuousClock().now) -> Bool {
        remaining(at: now) <= .zero
    }

    /**
     What the next request gets, which is the shorter of the two limits.

     A request started with two seconds of budget left does not get six, or the
     budget would be a suggestion rather than a bound.
     */
    func allowance(at now: ContinuousClock.Instant = ContinuousClock().now) -> Duration {
        min(Self.perRequest, remaining(at: now))
    }
}

/**
 Runs a request, and stops waiting for it once its allowance is gone.

 The request is cancelled, and the answer does not depend on the cancellation
 being honoured: this returns the moment the allowance is up, whatever the
 request does afterwards. That distinction is the whole point, and it is not
 free. A task group was the obvious way to write this and is wrong, because a
 group waits for its children when its body returns, cancelled or not: measured
 against a request with no suspension point to cancel at, it returned the right
 answer three seconds late, which is exactly the hang this exists to end.

 An abandoned request goes on running until it notices or finishes. Nothing
 waits for it and its answer is dropped.

 Nil for a request that ran out of time, which is the same answer as a request
 that failed, because the outcome is the same: the chunk is left as written.
 */
func answered<Result: Sendable>(
    within allowance: Duration,
    by request: @escaping @Sendable () async -> Result?
) async -> Result? {
    guard allowance > .zero else { return nil }

    let winner = FirstAnswer<Result>()

    return await withCheckedContinuation { continuation in
        let work = Task {
            let value = await request()
            winner.settle(continuation, with: value)
        }

        Task {
            try? await Task.sleep(for: allowance)
            work.cancel()
            winner.settle(continuation, with: nil)
        }
    }
}

/**
 Makes sure exactly one of the two answers is the one that counts.

 Both arrive eventually, since abandoning a request does not stop it, and
 resuming a continuation twice is not a race to lose, it crashes.
 */
private final class FirstAnswer<Result: Sendable>: Sendable {
    private let hasSettled = Mutex(false)

    func settle(_ continuation: CheckedContinuation<Result?, Never>, with value: Result?) {
        let isFirst = hasSettled.withLock { settled in
            defer { settled = true }

            return !settled
        }

        guard isFirst else { return }

        continuation.resume(returning: value)
    }
}
