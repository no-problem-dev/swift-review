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

/// What a declared system-prompt moment needs before it may ask.
public struct ReviewMomentRule: Hashable, Sendable {

    /// How many signals have to be counted (after ``ReviewPolicy/signalCapPerScope`` is applied).
    ///
    /// Defaults to 3: ask at the third time the app proved useful (rating.md R8).
    public var minimumSignals: Int

    /// Which kinds count toward ``minimumSignals``; `nil` counts every kind.
    public var countedSignals: Set<ReviewSignalKind>?

    public init(minimumSignals: Int = 3, countedSignals: Set<ReviewSignalKind>? = nil) {
        self.minimumSignals = minimumSignals
        self.countedSignals = countedSignals
    }
}

/// What a declared own-screen moment needs before the app shows its own review screen.
///
/// An own-screen moment never calls the system prompt, so it does not spend the system's three
/// prompts a year. That is why it is free of the days-of-use, signal, 60-day and yearly rules, and
/// holds two things of its own: once per version, and a wait after the person pressed the screen's
/// rate button (``ReviewPrompter/markRated()``).
///
/// It shares two things with the system prompt, because they are about the person, not about the
/// allowance: the days since install (``minimumDaysSinceInstall``, the policy's 7 by default; R5,
/// R9), and blockers, because a screen right after a paywall or an error is as badly timed as a
/// prompt (R10, R25).
public struct ReviewScreenRule: Hashable, Sendable {

    /// Elapsed days after ``ReviewPrompter/markRated()`` during which the screen is not shown again,
    /// even in a new version. Defaults to 120, the value gamification-app's `ReviewAskGate` and
    /// reading-memory's `ReviewAsk` use for the same screen (rating.md R24). Someone who closed the
    /// screen without rating sees it again in the next version.
    public var daysAfterRated: Int

    /// Elapsed days since the first recorded launch before the screen is shown. `nil` (the default)
    /// uses ``ReviewPolicy/minimumDaysSinceInstall``; `0` turns the rule off for this screen.
    ///
    /// Someone who installed yesterday and updated today sees What's New, but has not yet had the
    /// time to find the app useful, and a rating asked for before that comes out low (R5, R9).
    public var minimumDaysSinceInstall: Int?

    public init(daysAfterRated: Int = 120, minimumDaysSinceInstall: Int? = nil) {
        self.daysAfterRated = daysAfterRated
        self.minimumDaysSinceInstall = minimumDaysSinceInstall
    }
}

/// Every threshold the decision uses, as values the app passes in.
///
/// **There is one set of defaults, and it is studio's rating rules** (`knowledge/rating.md`, the R
/// numbers on each property). An app passes only its moments, and overrides a value only with a
/// reason it can write down next to it:
///
/// ```swift
/// let policy = ReviewPolicy(moments: [.bookCompleted: ReviewMomentRule()],
///                           screens: [.afterWhatsNew: ReviewScreenRule()])
/// ```
///
/// Nothing is declared as a moment by default; until the app lists one, nothing ever asks.
///
/// ## The system limit is not a target
///
/// iOS shows the prompt at most three times in 365 days per app and does not report whether it did.
/// ``maximumAsksPerYear`` counts **calls**, so a value above
/// ``ReviewPolicy/systemLimitPerYear`` only spends requests the system will quietly drop.
public struct ReviewPolicy: Sendable, Equatable {

    /// The most prompts iOS shows per app in any 365-day period.
    public static let systemLimitPerYear = 3

    /// How long each built-in blocker holds requests back (rating.md R25): paywall closed 14 days,
    /// an error 3 days, feedback sent 30 days, the cancel screen opened 90 days.
    ///
    /// Add an app's own kinds with `ReviewPolicy.standardCooldowns.merging([...]) { $1 }`.
    public static let standardCooldowns: [ReviewBlockerKind: ReviewCooldown] = [
        .paywallDismissed: .days(14),
        .error: .days(3),
        .feedbackSent: .days(30),
        .cancelScreenOpened: .days(90)
    ]

    /// A switch to stop all requests and screens without shipping a build, such as from remote
    /// configuration.
    public var isEnabled: Bool

    /// The zone in which "a day of use" is counted.
    public var timeZone: TimeZone

    /// Elapsed days since the first recorded launch before any request. Default 7 (R9).
    public var minimumDaysSinceInstall: Int

    /// Distinct calendar days on which the app was opened before any request. Default 0: the rating
    /// rules have no such rule (R9 counts days since install), so it is off unless an app sets it.
    public var minimumActiveDays: Int

    /// How many recent days of use are kept. Older ones are dropped from state.
    public var activeDayRetention: Int

    /// Seconds since this launch (the prompter's first ``ReviewPrompter/markActive()``) before any
    /// request. Default 30 (R9).
    public var minimumSecondsSinceLaunch: Int

    /// The only places that may call the system prompt, with what each needs.
    public var moments: [ReviewMomentName: ReviewMomentRule]

    /// The only places that may show the app's own review screen, with what each needs. Kept apart
    /// from ``moments`` because the two spend different things (see ``ReviewScreenRule``).
    public var screens: [ReviewMomentName: ReviewScreenRule]

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
    /// holds nothing back. Default ``standardCooldowns`` (R25).
    public var cooldowns: [ReviewBlockerKind: ReviewCooldown]

    /// Requests per version, at ``versionGranularity``. Default 1 (R9: not yet asked in this version).
    public var asksPerVersion: Int

    /// Which part of the version number makes a version new. Default `.minor`, so a fix-only
    /// release does not earn another request.
    public var versionGranularity: AppVersion.Granularity

    /// Elapsed days required after the previous request. Default 60 (R9): with the system's three
    /// prompts a year, 60 days apart still uses the whole allowance.
    public var minimumDaysBetweenAsks: Int

    /// Requests in any rolling 365-day window, counting every call. Default
    /// ``systemLimitPerYear`` (R9).
    public var maximumAsksPerYear: Int

    /// Requests per scope; `nil` (the default) for no limit. `1` means "the same trip is never asked
    /// about twice". The rating rules have no per-scope rule; apps with scopes set it.
    public var asksPerScope: Int?

    /// How long signals are kept in state at all.
    public var signalRetentionDays: Int

    public init(
        isEnabled: Bool = true,
        timeZone: TimeZone = .current,
        minimumDaysSinceInstall: Int = 7,
        minimumActiveDays: Int = 0,
        activeDayRetention: Int = 60,
        minimumSecondsSinceLaunch: Int = 30,
        moments: [ReviewMomentName: ReviewMomentRule] = [:],
        screens: [ReviewMomentName: ReviewScreenRule] = [:],
        signalCapPerScope: [ReviewSignalKind: Int] = [:],
        unscopedSignalLookbackDays: Int? = nil,
        cooldowns: [ReviewBlockerKind: ReviewCooldown] = ReviewPolicy.standardCooldowns,
        asksPerVersion: Int = 1,
        versionGranularity: AppVersion.Granularity = .minor,
        minimumDaysBetweenAsks: Int = 60,
        maximumAsksPerYear: Int = ReviewPolicy.systemLimitPerYear,
        asksPerScope: Int? = nil,
        signalRetentionDays: Int = 365
    ) {
        self.isEnabled = isEnabled
        self.timeZone = timeZone
        self.minimumDaysSinceInstall = minimumDaysSinceInstall
        self.minimumActiveDays = minimumActiveDays
        self.activeDayRetention = activeDayRetention
        self.minimumSecondsSinceLaunch = minimumSecondsSinceLaunch
        self.moments = moments
        self.screens = screens
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
