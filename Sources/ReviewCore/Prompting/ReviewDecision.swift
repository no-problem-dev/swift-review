import Foundation

/// Whether a moment may call the system's review request, and if not, the first reason why.
public enum ReviewDecision: Hashable, Sendable {

    /// Call the system now. The system still decides whether a prompt appears.
    case ask

    /// Do not call. The reason is the first rule that failed, in the order prerequisites →
    /// blockers → limits.
    case skip(ReviewSkipReason)

    /// `true` when the person met every prerequisite, so a skip is "eligible but held back".
    ///
    /// This is the line between "not yet" and "not now". A high share of blocker skips points at the
    /// part of the app that produces the blocker (paywall, errors), not at the thresholds.
    public var passedPrerequisites: Bool {
        switch self {
        case .ask: true
        case let .skip(reason): reason.stage != .prerequisite
        }
    }
}

/// Why a moment did not ask.
public enum ReviewSkipReason: Hashable, Sendable {

    // MARK: Prerequisites

    /// ``ReviewPolicy/isEnabled`` is off.
    case disabled
    /// The moment is not listed in ``ReviewPolicy/moments``.
    case undeclaredMoment(ReviewMomentName)
    /// Stored state could not be read; nothing is asked and nothing is overwritten.
    case stateUnavailable
    /// Fewer elapsed days since the first launch than required. `days` is 0 before any launch is recorded.
    case tooSoonAfterInstall(days: Int, required: Int)
    /// Fewer distinct days of use than required.
    case tooFewActiveDays(count: Int, required: Int)
    /// An app-specific prerequisite does not hold.
    case requirementUnmet(ReviewRequirement)
    /// Fewer counted signals than the moment needs.
    case tooFewSignals(count: Int, required: Int)

    // MARK: Blockers

    /// A condition in effect right now, such as being offline.
    case ongoing(ReviewBlockerKind)
    /// A recorded blocker is still cooling down. `until` is `nil` while it holds for the whole scope.
    case coolingDown(ReviewBlockerKind, until: Date?)

    // MARK: Limits

    /// A request already happened in this version.
    case alreadyAskedThisVersion(AppVersion)
    /// A request already happened in this scope.
    case alreadyAskedInScope(ReviewScope)
    /// The previous request was too recent.
    case tooSoonAfterLastAsk(until: Date)
    /// The rolling 365-day limit is used up until the given instant.
    case yearlyLimitReached(until: Date)
    /// Another request is waiting for the screen right now.
    case askInProgress

    /// Which group of rules the reason belongs to.
    public enum Stage: String, Sendable, Hashable {
        case prerequisite
        case blocker
        case limit
    }

    public var stage: Stage {
        switch self {
        case .disabled, .undeclaredMoment, .stateUnavailable, .tooSoonAfterInstall, .tooFewActiveDays,
             .requirementUnmet, .tooFewSignals:
            .prerequisite
        case .ongoing, .coolingDown:
            .blocker
        case .alreadyAskedThisVersion, .alreadyAskedInScope, .tooSoonAfterLastAsk, .yearlyLimitReached,
             .askInProgress:
            .limit
        }
    }

    /// A stable snake_case name for metrics. For blockers and requirements it is the app's own name,
    /// so "blocked by paywall_dismissed" reads directly.
    public var code: String {
        switch self {
        case .disabled: "disabled"
        case .undeclaredMoment: "undeclared_moment"
        case .stateUnavailable: "state_unavailable"
        case .tooSoonAfterInstall: "too_soon_after_install"
        case .tooFewActiveDays: "too_few_active_days"
        case let .requirementUnmet(requirement): requirement.rawValue
        case .tooFewSignals: "too_few_signals"
        case let .ongoing(kind): kind.rawValue
        case let .coolingDown(kind, _): kind.rawValue
        case .alreadyAskedThisVersion: "already_asked_this_version"
        case .alreadyAskedInScope: "already_asked_in_scope"
        case .tooSoonAfterLastAsk: "too_soon_after_last_ask"
        case .yearlyLimitReached: "yearly_limit_reached"
        case .askInProgress: "ask_in_progress"
        }
    }
}
