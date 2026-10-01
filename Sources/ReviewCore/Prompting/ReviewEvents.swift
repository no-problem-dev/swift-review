import Foundation

/// One good outcome, counted toward asking.
public struct ReviewSignal: Hashable, Sendable, Codable {

    public var kind: ReviewSignalKind
    /// The group it belongs to, or `nil` when the app does not group this kind.
    public var scope: ReviewScope?
    public var at: Date

    public init(_ kind: ReviewSignalKind, in scope: ReviewScope? = nil, at: Date) {
        self.kind = kind
        self.scope = scope
        self.at = at
    }
}

/// The last time something that holds a request back happened.
///
/// State keeps only the latest one per kind and scope: a cooldown runs from the most recent
/// occurrence, so earlier ones never change an answer.
public struct ReviewBlocker: Hashable, Sendable, Codable {

    public var kind: ReviewBlockerKind
    /// Where it happened, or `nil` when it concerns the whole app.
    public var scope: ReviewScope?
    public var at: Date

    public init(_ kind: ReviewBlockerKind, in scope: ReviewScope? = nil, at: Date) {
        self.kind = kind
        self.scope = scope
        self.at = at
    }
}

/// One call to the system's review request.
///
/// **Recorded whenever the app called the system, whether or not a prompt appeared.** The system
/// never says whether it showed one, so counting only displayed prompts is impossible, and not
/// counting at all would let the app call again at every moment while the system stays quiet.
public struct ReviewAsk: Hashable, Sendable, Codable {

    public var at: Date
    public var version: AppVersion
    public var moment: ReviewMomentName
    public var scope: ReviewScope?

    public init(at: Date, version: AppVersion, moment: ReviewMomentName, scope: ReviewScope? = nil) {
        self.at = at
        self.version = version
        self.moment = moment
        self.scope = scope
    }
}

/// A place in the app that has just been reached, together with what is true right now.
///
/// ```swift
/// let moment = ReviewMoment(
///     .journalSaved,
///     in: ReviewScope(trip.id),
///     ongoing: isOffline ? [.offline] : [],
///     unmet: ownTrips.isEmpty ? [.hasOwnTrip] : []
/// )
/// ```
public struct ReviewMoment: Hashable, Sendable {

    public var name: ReviewMomentName
    /// The group whose signals are counted. `nil` counts every signal since the last request.
    public var scope: ReviewScope?
    /// Conditions in effect at this instant that rule a request out, such as being offline or
    /// showing a sheet. They are not stored.
    public var ongoing: Set<ReviewBlockerKind>
    /// App-specific prerequisites that do not hold right now.
    public var unmet: Set<ReviewRequirement>

    public init(
        _ name: ReviewMomentName,
        in scope: ReviewScope? = nil,
        ongoing: Set<ReviewBlockerKind> = [],
        unmet: Set<ReviewRequirement> = []
    ) {
        self.name = name
        self.scope = scope
        self.ongoing = ongoing
        self.unmet = unmet
    }
}
