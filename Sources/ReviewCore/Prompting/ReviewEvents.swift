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
    /// The group whose signals are counted. `nil` counts unscoped signals since the last request.
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

/// A place where the app may show **its own** review screen, together with what is true right now.
///
/// This is the second kind of moment, and it is a separate type on purpose. A ``ReviewMoment``
/// calls the system prompt and spends one of its three prompts a year; a `ReviewScreenMoment`
/// never reaches the system and spends nothing, so it is decided by its own, smaller rule
/// (``ReviewScreenRule``) and goes through ``ReviewPrompter/present(_:)``, which has no asker.
/// The compiler therefore keeps "show our screen" from ever turning into a system call.
///
/// The screen itself is the app's (rating.md R24: try it in one app and read the review outcome
/// before spreading it). The package only decides whether it may appear now.
///
/// ```swift
/// // After the What's New sheet closed, for someone who upgraded:
/// if await prompter.present(ReviewScreenMoment(.afterWhatsNew)) == .ask {
///     showReviewScreen = true
/// }
/// ```
public struct ReviewScreenMoment: Hashable, Sendable {

    public var name: ReviewMomentName
    /// Conditions in effect at this instant that rule the screen out. They are not stored.
    public var ongoing: Set<ReviewBlockerKind>
    /// App-specific prerequisites that do not hold right now, such as "has received what the app
    /// promises". Checked like a ``ReviewMoment``'s, as a prerequisite.
    public var unmet: Set<ReviewRequirement>

    public init(
        _ name: ReviewMomentName,
        ongoing: Set<ReviewBlockerKind> = [],
        unmet: Set<ReviewRequirement> = []
    ) {
        self.name = name
        self.ongoing = ongoing
        self.unmet = unmet
    }
}

/// One time the app's own review screen was allowed to appear. Kept apart from ``ReviewAsk``,
/// because it does not count toward any system limit.
public struct ReviewScreenShow: Hashable, Sendable, Codable {

    public var at: Date
    public var version: AppVersion
    public var moment: ReviewMomentName

    public init(at: Date, version: AppVersion, moment: ReviewMomentName) {
        self.at = at
        self.version = version
        self.moment = moment
    }
}
