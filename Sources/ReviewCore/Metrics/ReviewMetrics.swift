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
/// The prompter sends the first four itself. The rest are moments only the app sees, sent through
/// the same port so that everything about ratings and feedback reads as one set.
public enum ReviewMetricEvent: Hashable, Sendable {

    /// A declared moment was reached and decided.
    case evaluated(ReviewMoment, ReviewDecision)
    /// The system's request was called. `ordinal` is how many calls this device's state now holds.
    case requested(ReviewMoment, version: AppVersion, ordinal: Int)
    /// A request was dropped before reaching the system.
    case abandoned(ReviewMoment, ReviewAbandonment)
    /// Stored state could not be read or written.
    case stateUnavailable(ReviewStoreError)
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
        case .requested: "review_prompt_requested"
        case .abandoned: "review_prompt_abandoned"
        case .stateUnavailable: "review_state_unavailable"
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
        case let .requested(moment, version, ordinal):
            return [
                "moment": .text(moment.name.rawValue),
                "app_version": .text(version.description),
                "nth": .count(ordinal)
            ]
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

/// Where metrics go. Fire-and-forget: nothing returns and nothing throws.
///
/// The package does not depend on `swift-analytics`; a bridge is a few lines in the app (see the
/// README).
public protocol ReviewMetrics: Sendable {
    func record(_ event: ReviewMetricEvent)
}

/// Discards every metric.
public struct NoReviewMetrics: ReviewMetrics {
    public init() {}
    public func record(_ event: ReviewMetricEvent) {}
}
