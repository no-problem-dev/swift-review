import Foundation

/// What happened when the prompter handed a request to the screen.
public enum ReviewAskOutcome: Hashable, Sendable {

    /// The system's review request was called. Whether a prompt appeared is unknown and unknowable.
    case requested

    /// The request was dropped before the system was called. **It is not counted.**
    case abandoned(ReviewAbandonment)
}

/// Why a request was dropped before reaching the system.
public enum ReviewAbandonment: String, Hashable, Sendable, CaseIterable {
    /// No screen was attached to take requests.
    case noHost = "no_host"
    /// Another request was already waiting.
    case alreadyPending = "already_pending"
    /// The app left the foreground while waiting.
    case sceneInactive = "scene_inactive"
    /// A sheet or dialog was on screen while waiting.
    case obstructed
    /// The screen went away while waiting.
    case interrupted
}

/// The port through which the prompter calls the system's review request.
///
/// The production conformance is `ReviewRequestBridge` in `ReviewSwiftUI`, the only place that
/// imports StoreKit. Implementations call the system **at most once per call** and report what they
/// did; they never retry.
public protocol ReviewAsker: Sendable {
    func requestReview(for moment: ReviewMoment) async -> ReviewAskOutcome
}

/// The current time, injected so tests can move it.
public protocol ReviewClock: Sendable {
    func now() -> Date
}

/// The wall clock.
public struct SystemReviewClock: ReviewClock {
    public init() {}
    public func now() -> Date { Date() }
}
