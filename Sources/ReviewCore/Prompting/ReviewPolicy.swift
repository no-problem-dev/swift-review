import Foundation

/// How long a recorded blocker holds requests back.
public struct ReviewCooldown: Hashable, Sendable {

    /// Days after the blocker during which no moment may ask. Measured in elapsed 24-hour periods
    /// from the instant it was recorded.
    public var days: Int

    /// When the blocker was recorded in a scope, moments **in that same scope** stay held back until
    /// the scope is forgotten, however many days pass. Moments elsewhere wait only ``days``.
    ///
    /// For "a trip with a missed connection is never the trip we ask about, but the next trip may be
    /// asked about three days later", record the blocker in the trip's scope with
    /// `ReviewCooldown(days: 3, holdsForScope: true)`. Has no effect on a blocker recorded without a
    /// scope.
    public var holdsForScope: Bool

    public init(days: Int, holdsForScope: Bool = false) {
        self.days = days
        self.holdsForScope = holdsForScope
    }

    /// Held back for a number of days, everywhere.
    public static func days(_ days: Int) -> ReviewCooldown { ReviewCooldown(days: days) }
}

/// What a declared moment needs before it may ask.
public struct ReviewMomentRule: Hashable, Sendable {

    /// How many signals have to be counted (after ``ReviewPolicy/signalCapPerScope`` is applied).
    public var minimumSignals: Int

    /// Which kinds count toward ``minimumSignals``; `nil` counts every kind.
    public var countedSignals: Set<ReviewSignalKind>?

    public init(minimumSignals: Int, countedSignals: Set<ReviewSignalKind>? = nil) {
        self.minimumSignals = minimumSignals
        self.countedSignals = countedSignals
    }
}

/// Every threshold the decision uses, as values the app passes in.
///
/// The defaults follow the research this package was designed from (Apple's HIG and StoreKit
/// documentation, and the tabisaki review spec): wait a week after install and three separate days
/// of use, ask at most once per minor version, leave 120 days between requests, and stay at or
/// under the system's own limit of three per 365 days. Nothing is declared as a moment by default;
/// until the app lists one, nothing ever asks.
///
/// ## The system limit is not a target
///
/// iOS shows the prompt at most three times in 365 days per app and does not report whether it did.
/// ``maximumAsksPerYear`` counts **calls**, so a value above
/// ``ReviewPolicy/systemLimitPerYear`` only spends requests the system will quietly drop.
public struct ReviewPolicy: Sendable, Equatable {

    /// The most prompts iOS shows per app in any 365-day period.
    public static let systemLimitPerYear = 3

    /// A switch to stop all requests without shipping a build, such as from remote configuration.
    public var isEnabled: Bool

    /// The zone in which "a day of use" is counted.
    public var timeZone: TimeZone

    /// Elapsed days since the first recorded launch before any request.
    public var minimumDaysSinceInstall: Int

    /// Distinct calendar days on which the app was opened before any request.
    public var minimumActiveDays: Int

    /// How many recent days of use are kept. Older ones are dropped from state.
    public var activeDayRetention: Int

    /// The only places that may ask, with what each needs.
    public var moments: [ReviewMomentName: ReviewMomentRule]

    /// The most a single kind counts within one scope (or among unscoped signals), however often it
    /// happens. Kinds without an entry are not capped. `[.checkedIn: 1]` makes ten check-ins on one
    /// trip count as one.
    public var signalCapPerScope: [ReviewSignalKind: Int]

    /// For moments without a scope, how far back unscoped signals are counted. Only signals after
    /// the most recent request count in any case, so one run of good outcomes never earns two
    /// requests. Signals recorded in a scope never count toward a moment without one.
    /// `nil` sets no further limit.
    public var unscopedSignalLookbackDays: Int?

    /// How long each kind of recorded blocker holds requests back. A recorded kind with no entry
    /// holds nothing back.
    public var cooldowns: [ReviewBlockerKind: ReviewCooldown]

    /// Requests per version, at ``versionGranularity``.
    public var asksPerVersion: Int

    /// Which part of the version number makes a version new.
    public var versionGranularity: AppVersion.Granularity

    /// Elapsed days required after the previous request.
    public var minimumDaysBetweenAsks: Int

    /// Requests in any rolling 365-day window, counting every call.
    public var maximumAsksPerYear: Int

    /// Requests per scope; `nil` for no limit. `1` means "the same trip is never asked about twice".
    public var asksPerScope: Int?

    /// How long signals are kept in state at all.
    public var signalRetentionDays: Int

    public init(
        isEnabled: Bool = true,
        timeZone: TimeZone,
        minimumDaysSinceInstall: Int = 7,
        minimumActiveDays: Int = 3,
        activeDayRetention: Int = 60,
        moments: [ReviewMomentName: ReviewMomentRule],
        signalCapPerScope: [ReviewSignalKind: Int] = [:],
        unscopedSignalLookbackDays: Int? = nil,
        cooldowns: [ReviewBlockerKind: ReviewCooldown] = [:],
        asksPerVersion: Int = 1,
        versionGranularity: AppVersion.Granularity = .minor,
        minimumDaysBetweenAsks: Int = 120,
        maximumAsksPerYear: Int = ReviewPolicy.systemLimitPerYear,
        asksPerScope: Int? = 1,
        signalRetentionDays: Int = 365
    ) {
        self.isEnabled = isEnabled
        self.timeZone = timeZone
        self.minimumDaysSinceInstall = minimumDaysSinceInstall
        self.minimumActiveDays = minimumActiveDays
        self.activeDayRetention = activeDayRetention
        self.moments = moments
        self.signalCapPerScope = signalCapPerScope
        self.unscopedSignalLookbackDays = unscopedSignalLookbackDays
        self.cooldowns = cooldowns
        self.asksPerVersion = asksPerVersion
        self.versionGranularity = versionGranularity
        self.minimumDaysBetweenAsks = minimumDaysBetweenAsks
        self.maximumAsksPerYear = maximumAsksPerYear
        self.asksPerScope = asksPerScope
        self.signalRetentionDays = signalRetentionDays
    }
}
