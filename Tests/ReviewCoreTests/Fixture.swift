import Foundation
import ReviewCore

/// The tabisaki spec's values, used as one realistic policy across the tests.
enum Fixture {

    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static let utc = TimeZone(identifier: "UTC")!

    // Moments
    static let journalSaved: ReviewMomentName = "journal_saved"
    static let splitSettled: ReviewMomentName = "split_settled"
    static let nextTripPlanned: ReviewMomentName = "next_trip_planned"

    // Signals
    static let movementDecided: ReviewSignalKind = "movement_decided"
    static let stayAdded: ReviewSignalKind = "stay_added"
    static let checkedIn: ReviewSignalKind = "checked_in"
    static let journalSignal: ReviewSignalKind = "journal_saved"

    // Blockers
    static let paywallDismissed: ReviewBlockerKind = "paywall_dismissed"
    static let error: ReviewBlockerKind = "error"
    static let syncReverted: ReviewBlockerKind = "sync_reverted"
    static let tripDisrupted: ReviewBlockerKind = "trip_disrupted"
    static let feedbackSent: ReviewBlockerKind = "feedback_sent"
    static let cancelScreen: ReviewBlockerKind = "cancel_screen_opened"
    static let offline: ReviewBlockerKind = "offline"
    static let sheetShown: ReviewBlockerKind = "sheet_shown"

    // Requirements
    static let hasOwnTrip: ReviewRequirement = "has_own_trip"

    static let tripA: ReviewScope = "trip-a"
    static let tripB: ReviewScope = "trip-b"

    static let v1_0 = AppVersion(major: 1, minor: 0)
    static let v1_0_1 = AppVersion(major: 1, minor: 0, patch: 1)
    static let v1_1 = AppVersion(major: 1, minor: 1)
    static let v1_2 = AppVersion(major: 1, minor: 2)
    static let v1_3 = AppVersion(major: 1, minor: 3)

    /// 2026-10-01 12:00 in Tokyo.
    static let now = date(2026, 10, 1, 12)

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0,
                     in zone: TimeZone = tokyo) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func days(_ count: Double) -> TimeInterval { count * 86_400 }

    static func policy(
        isEnabled: Bool = true,
        timeZone: TimeZone = tokyo,
        unscopedSignalLookbackDays: Int? = nil,
        versionGranularity: AppVersion.Granularity = .minor,
        maximumAsksPerYear: Int = 3
    ) -> ReviewPolicy {
        ReviewPolicy(
            isEnabled: isEnabled,
            timeZone: timeZone,
            moments: [
                journalSaved: ReviewMomentRule(minimumSignals: 2),
                splitSettled: ReviewMomentRule(minimumSignals: 2),
                nextTripPlanned: ReviewMomentRule(minimumSignals: 1, countedSignals: [movementDecided, stayAdded])
            ],
            signalCapPerScope: [checkedIn: 1, journalSignal: 1],
            unscopedSignalLookbackDays: unscopedSignalLookbackDays,
            cooldowns: [
                paywallDismissed: .days(14),
                error: .days(3),
                syncReverted: .days(3),
                tripDisrupted: ReviewCooldown(days: 3, holdsForScope: true),
                feedbackSent: .days(30),
                cancelScreen: .days(90)
            ],
            versionGranularity: versionGranularity,
            maximumAsksPerYear: maximumAsksPerYear
        )
    }

    /// Installed 30 days before `now`, opened on five days, two signals in trip A.
    static func eligibleState(at now: Date = now, scope: ReviewScope? = tripA) -> ReviewState {
        let days = (0..<5).compactMap { ReviewDay(now.addingTimeInterval(-Fixture.days(Double($0))), in: tokyo) }
        return ReviewState(
            installedAt: now.addingTimeInterval(-Fixture.days(30)),
            activeDays: days,
            signals: [
                ReviewSignal(movementDecided, in: scope, at: now.addingTimeInterval(-Fixture.days(2))),
                ReviewSignal(stayAdded, in: scope, at: now.addingTimeInterval(-Fixture.days(1)))
            ]
        )
    }

    static func decide(
        _ moment: ReviewMoment = ReviewMoment(journalSaved, in: tripA),
        state: ReviewState = eligibleState(),
        at instant: Date = now,
        version: AppVersion = v1_0,
        policy: ReviewPolicy = policy()
    ) -> ReviewDecision {
        ReviewRules.decide(at: instant, version: version, moment: moment, state: state, policy: policy)
    }
}

extension ReviewState {
    func adding(_ signal: ReviewSignal) -> ReviewState {
        var copy = self
        copy.record(signal)
        return copy
    }

    func adding(_ blocker: ReviewBlocker) -> ReviewState {
        var copy = self
        copy.record(blocker)
        return copy
    }

    func adding(_ ask: ReviewAsk) -> ReviewState {
        var copy = self
        copy.record(ask)
        return copy
    }
}
