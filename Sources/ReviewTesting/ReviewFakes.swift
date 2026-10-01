import Foundation
import ReviewCore

/// A clock that stands still until moved.
///
/// ```swift
/// let clock = ManualReviewClock(Date(timeIntervalSince1970: 1_800_000_000))
/// clock.advance(days: 7)
/// ```
public final class ManualReviewClock: ReviewClock {

    private let current: Locked<Date>

    public init(_ start: Date) {
        current = Locked(start)
    }

    public func now() -> Date { current.value }

    /// Moves to an instant.
    public func set(_ instant: Date) {
        current.withValue { $0 = instant }
    }

    /// Moves forward by whole 24-hour periods.
    public func advance(days: Int) {
        advance(seconds: Double(days) * 86_400)
    }

    public func advance(hours: Double) {
        advance(seconds: hours * 3_600)
    }

    public func advance(seconds: TimeInterval) {
        current.withValue { $0 = $0.addingTimeInterval(seconds) }
    }
}

/// An asker that answers with a preset outcome and remembers every moment it was handed.
///
/// It stands where `ReviewRequestBridge` stands in the app, so a test pins "this flow asks exactly
/// once, at this moment" without a screen. `RequestReviewAction` itself cannot be faked (it has no
/// public initialiser), which is why the seam is here.
public final class RecordingReviewAsker: ReviewAsker {

    private let state: Locked<(outcome: ReviewAskOutcome, moments: [ReviewMoment])>

    public init(answering outcome: ReviewAskOutcome = .requested) {
        state = Locked((outcome, []))
    }

    /// Every moment handed over, in order. **Repeats are left in.**
    public var moments: [ReviewMoment] { state.value.moments }

    /// How many times the system would have been called.
    public var count: Int { moments.count }

    /// Changes the answer for later calls.
    public func answer(_ outcome: ReviewAskOutcome) {
        state.withValue { $0.outcome = outcome }
    }

    public func requestReview(for moment: ReviewMoment) async -> ReviewAskOutcome {
        state.withValue { current in
            current.moments.append(moment)
            return current.outcome
        }
    }
}

/// Metrics kept in order, repeats included.
public final class RecordingReviewMetrics: ReviewMetrics {

    private let storage = Locked<[ReviewMetricEvent]>([])

    public init() {}

    public var events: [ReviewMetricEvent] { storage.value }

    /// The names, in order.
    public var names: [String] { events.map(\.name) }

    public func record(_ event: ReviewMetricEvent) {
        storage.withValue { $0.append(event) }
    }

    public func reset() {
        storage.withValue { $0.removeAll() }
    }
}

/// A feedback sender that keeps what it was given and answers with a preset result.
public final class RecordingFeedbackSender: FeedbackSender {

    private let state: Locked<(result: Result<FeedbackDelivery, FeedbackError>, sent: [Feedback])>

    public init(answering result: Result<FeedbackDelivery, FeedbackError> = .success(.delivered(receipt: nil))) {
        state = Locked((result, []))
    }

    /// Everything handed over, in order, including sends that were answered with an error.
    public var sent: [Feedback] { state.value.sent }

    public func send(_ feedback: Feedback) async throws(FeedbackError) -> FeedbackDelivery {
        let result = state.withValue { current in
            current.sent.append(feedback)
            return current.result
        }
        return try result.get()
    }
}
