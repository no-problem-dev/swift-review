import Foundation

/// A value carried on a metric, limited to what every analytics destination accepts.
///
/// The cases match `swift-analytics`' `AnalyticsValue` one to one (`text`, `count`, `flag`), so a
/// bridge maps them without deciding anything.
public enum ReviewMetricValue: Hashable, Sendable, CustomStringConvertible {
    case text(String)
    case count(Int)
    case flag(Bool)

    public var description: String {
        switch self {
        case let .text(value): value
        case let .count(value): String(value)
        case let .flag(value): value ? "true" : "false"
        }
    }
}

/// Something worth measuring about requests and feedback.
///
/// The prompter sends the first six itself. The rest are moments only the app sees, sent through
/// the same port so that everything about ratings and feedback reads as one set.
///
/// ## The common catalog
///
/// Only ``requested(_:ordinal:)`` is in the common analytics catalog (`swift-analytics`
/// `Schema/common/common.yaml`): `review_requested` with the one parameter `moment`, which is what
/// studio counts across apps. ``isInCommonCatalog`` marks it, so an app that sends only catalog
/// events forwards that one. The others are optional and app-specific; an app that sends them
/// declares them in its own catalog.
public enum ReviewMetricEvent: Hashable, Sendable {

    /// A declared system-prompt moment was reached and decided.
    case evaluated(ReviewMoment, ReviewDecision)
    /// The system's request was called (`review_requested`). Whether a prompt appeared is unknown.
    /// `ordinal` is how many calls this device's state now holds; it is not a catalog parameter,
    /// and an app that wants it (R20's `count`) adds it in its own catalog.
    case requested(ReviewMoment, ordinal: Int)
    /// A request was dropped before reaching the system.
    case abandoned(ReviewMoment, ReviewAbandonment)
    /// Stored state could not be read or written.
    case stateUnavailable(ReviewStoreError)
    /// A declared own-screen moment was reached and decided.
    case screenEvaluated(ReviewScreenMoment, ReviewDecision)
    /// The app's own review screen was allowed to appear. Not a `review_requested`: the system was
    /// not called.
    case screenShown(ReviewScreenMoment)
    /// The person opened the write-review page from the app's own link.
    case writeReviewLinkOpened
    /// The feedback screen was opened, from `source` (such as `settings` or `error_screen`).
    case feedbackOpened(source: String)
    /// Feedback left the app.
    case feedbackSent(kind: FeedbackKind, includesDiagnostics: Bool, delivery: FeedbackDelivery)

    /// A snake_case name for analytics.
    public var name: String {
        switch self {
        case .evaluated: "review_prompt_evaluated"
        case .requested: "review_requested"
        case .abandoned: "review_prompt_abandoned"
        case .stateUnavailable: "review_state_unavailable"
        case .screenEvaluated: "review_screen_evaluated"
        case .screenShown: "review_screen_shown"
        case .writeReviewLinkOpened: "review_link_opened"
        case .feedbackOpened: "feedback_opened"
        case .feedbackSent: "feedback_sent"
        }
    }

    /// Parameters for analytics. Never carries text the person wrote, or the scope's identifier.
    public var parameters: [String: ReviewMetricValue] {
        switch self {
        case let .evaluated(moment, decision):
            var parameters: [String: ReviewMetricValue] = [
                "moment": .text(moment.name.rawValue),
                "eligible": .flag(decision.passedPrerequisites),
                "asked": .flag(decision == .ask)
            ]
            if case let .skip(reason) = decision {
                parameters["stage"] = .text(reason.stage.rawValue)
                parameters["reason"] = .text(reason.code)
            }
            return parameters
        case let .requested(moment, _):
            // Exactly the common catalog's parameters. The app version is the envelope's.
            return ["moment": .text(moment.name.rawValue)]
        case let .screenEvaluated(moment, decision):
            var parameters: [String: ReviewMetricValue] = [
                "moment": .text(moment.name.rawValue),
                "shown": .flag(decision == .ask)
            ]
            if case let .skip(reason) = decision {
                parameters["stage"] = .text(reason.stage.rawValue)
                parameters["reason"] = .text(reason.code)
            }
            return parameters
        case let .screenShown(moment):
            return ["moment": .text(moment.name.rawValue)]
        case let .abandoned(moment, reason):
            return ["moment": .text(moment.name.rawValue), "reason": .text(reason.rawValue)]
        case let .stateUnavailable(error):
            let reason = switch error {
            case .newerSchema: "newer_schema"
            case .corrupt: "corrupt"
            case .unencodable: "unencodable"
            }
            return ["reason": .text(reason)]
        case .writeReviewLinkOpened:
            return [:]
        case let .feedbackOpened(source):
            return ["source": .text(source)]
        case let .feedbackSent(kind, includesDiagnostics, delivery):
            return [
                "kind": .text(kind.rawValue),
                "diagnostics": .flag(includesDiagnostics),
                "channel": .text(delivery.channel)
            ]
        }
    }
}

extension ReviewMetricEvent {
    /// `true` for the events in the common analytics catalog (only `review_requested`).
    public var isInCommonCatalog: Bool {
        if case .requested = self { return true }
        return false
    }
}

/// Where metrics go. Fire-and-forget: nothing returns and nothing throws.
///
/// The package does not depend on `swift-analytics`; a bridge is a few lines in the app (see the
/// README).
public protocol ReviewMetrics: Sendable {
    func record(_ event: ReviewMetricEvent)
}

/// Hands every metric to a closure, so an app wires its analytics without declaring a type.
///
/// ```swift
/// let metrics = ReviewMetricsHandler { event in
///     guard event.isInCommonCatalog else { return }
///     analytics.track(name: event.name, parameters: event.parameters)
/// }
/// ```
public struct ReviewMetricsHandler: ReviewMetrics {
    private let handler: @Sendable (ReviewMetricEvent) -> Void

    public init(_ handler: @escaping @Sendable (ReviewMetricEvent) -> Void) {
        self.handler = handler
    }

    public func record(_ event: ReviewMetricEvent) { handler(event) }
}

/// Discards every metric.
public struct NoReviewMetrics: ReviewMetrics {
    public init() {}
    public func record(_ event: ReviewMetricEvent) {}
}
