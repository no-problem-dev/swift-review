import Foundation
import Testing
import ReviewCore

@Suite("前提: インストールからの日数・開いた日・合図")
struct PrerequisiteRuleTests {

    @Test("前提も止める出来事も上限も通れば頼む")
    func asksWhenEverythingHolds() {
        #expect(Fixture.decide() == .ask)
    }

    @Test("方針を止めていれば頼まない")
    func disabledPolicyNeverAsks() {
        #expect(Fixture.decide(policy: Fixture.policy(isEnabled: false)) == .skip(.disabled))
    }

    @Test("方針に無い場面では頼まない")
    func undeclaredMomentNeverAsks() {
        let decision = Fixture.decide(ReviewMoment("app_launched"))
        #expect(decision == .skip(.undeclaredMoment("app_launched")))
    }

    @Test("インストールから6日と23時間では頼まず、7日で頼む")
    func installAgeBoundary() {
        var state = Fixture.eligibleState()
        state.installedAt = Fixture.now.addingTimeInterval(-Fixture.days(7) + 3_600)
        #expect(Fixture.decide(state: state) == .skip(.tooSoonAfterInstall(days: 6, required: 7)))

        state.installedAt = Fixture.now.addingTimeInterval(-Fixture.days(7))
        #expect(Fixture.decide(state: state) == .ask)
    }

    @Test("起動の記録が無ければ、インストールの0日目として頼まない")
    func noLaunchRecordedIsDayZero() {
        var state = Fixture.eligibleState()
        state.installedAt = nil
        #expect(Fixture.decide(state: state) == .skip(.tooSoonAfterInstall(days: 0, required: 7)))
    }

    @Test("時計が戻っても日数は0より下にならない")
    func clockMovingBackwardsIsDayZero() {
        var state = Fixture.eligibleState()
        state.installedAt = Fixture.now.addingTimeInterval(Fixture.days(3))
        #expect(Fixture.decide(state: state) == .skip(.tooSoonAfterInstall(days: 0, required: 7)))
    }

    @Test("開いた日が2日では頼まず、3日で頼む")
    func activeDayBoundary() {
        var state = ReviewState(installedAt: Fixture.now.addingTimeInterval(-Fixture.days(30)))
        for offset in 0..<2 {
            state.markActive(at: Fixture.now.addingTimeInterval(-Fixture.days(Double(offset))),
                             in: Fixture.tokyo, retainingDays: 60)
        }
        state = state
            .adding(ReviewSignal(Fixture.movementDecided, in: Fixture.tripA, at: Fixture.now))
            .adding(ReviewSignal(Fixture.stayAdded, in: Fixture.tripA, at: Fixture.now))
        #expect(Fixture.decide(state: state) == .skip(.tooFewActiveDays(count: 2, required: 3)))

        state.markActive(at: Fixture.now.addingTimeInterval(-Fixture.days(10)), in: Fixture.tokyo, retainingDays: 60)
        #expect(Fixture.decide(state: state) == .ask)
    }

    @Test("同じ日に何度開いても1日と数える")
    func sameDayCountsOnce() {
        var state = ReviewState()
        for hour in [0.0, 3, 9, 20] {
            state.markActive(at: Fixture.date(2026, 10, 1, 0).addingTimeInterval(hour * 3_600),
                             in: Fixture.tokyo, retainingDays: 60)
        }
        #expect(state.activeDays == [ReviewDay(year: 2026, month: 10, day: 1)!])
    }

    @Test("日の区切りは方針の時間帯で数える（東京の23時半と0時半は2日、UTC では1日）")
    func dayBoundaryFollowsPolicyTimeZone() {
        let lateNight = Fixture.date(2026, 10, 1, 23, 30)
        let afterMidnight = Fixture.date(2026, 10, 2, 0, 30)

        var inTokyo = ReviewState()
        inTokyo.markActive(at: lateNight, in: Fixture.tokyo, retainingDays: 60)
        inTokyo.markActive(at: afterMidnight, in: Fixture.tokyo, retainingDays: 60)
        #expect(inTokyo.activeDays.count == 2)

        var inUTC = ReviewState()
        inUTC.markActive(at: lateNight, in: Fixture.utc, retainingDays: 60)
        inUTC.markActive(at: afterMidnight, in: Fixture.utc, retainingDays: 60)
        #expect(inUTC.activeDays.count == 1)
    }

    @Test("最初に開いた時刻だけをインストールの時刻にする")
    func installStampIsKeptFromTheFirstLaunch() {
        var state = ReviewState()
        state.markActive(at: Fixture.now, in: Fixture.tokyo, retainingDays: 60)
        state.markActive(at: Fixture.now.addingTimeInterval(Fixture.days(5)), in: Fixture.tokyo, retainingDays: 60)
        #expect(state.installedAt == Fixture.now)
    }

    @Test("保持の日数より前の開いた日は落とす")
    func oldActiveDaysAreDropped() {
        var state = ReviewState()
        state.markActive(at: Fixture.now.addingTimeInterval(-Fixture.days(61)), in: Fixture.tokyo, retainingDays: 60)
        state.markActive(at: Fixture.now.addingTimeInterval(-Fixture.days(59)), in: Fixture.tokyo, retainingDays: 60)
        state.markActive(at: Fixture.now, in: Fixture.tokyo, retainingDays: 60)
        #expect(state.activeDays.count == 2)
    }

    @Test("アプリの前提が欠けていれば頼まず、前提の段として扱う")
    func unmetRequirement() {
        let decision = Fixture.decide(ReviewMoment(Fixture.journalSaved, in: Fixture.tripA, unmet: [Fixture.hasOwnTrip]))
        #expect(decision == .skip(.requirementUnmet(Fixture.hasOwnTrip)))
        #expect(!decision.passedPrerequisites)
    }

    @Test("合図が1つでは頼まない")
    func tooFewSignals() {
        let state = ReviewState(
            installedAt: Fixture.eligibleState().installedAt,
            activeDays: Fixture.eligibleState().activeDays,
            signals: [ReviewSignal(Fixture.movementDecided, in: Fixture.tripA, at: Fixture.now)]
        )
        #expect(Fixture.decide(state: state) == .skip(.tooFewSignals(count: 1, required: 2)))
    }

    @Test("上限のある種類は、1つの範囲で何回あっても上限までしか数えない")
    func perKindCapWithinScope() {
        var state = ReviewState(installedAt: Fixture.eligibleState().installedAt,
                                activeDays: Fixture.eligibleState().activeDays)
        for hour in 0..<5 {
            state.record(ReviewSignal(Fixture.checkedIn, in: Fixture.tripA,
                                      at: Fixture.now.addingTimeInterval(-Double(hour) * 3_600)))
        }
        #expect(Fixture.decide(state: state) == .skip(.tooFewSignals(count: 1, required: 2)))

        state.record(ReviewSignal(Fixture.movementDecided, in: Fixture.tripA, at: Fixture.now))
        #expect(Fixture.decide(state: state) == .ask)
    }

    @Test("上限の無い種類は、あった回数だけ数える")
    func uncappedKindCountsEveryOccurrence() {
        let state = ReviewState(
            installedAt: Fixture.eligibleState().installedAt,
            activeDays: Fixture.eligibleState().activeDays,
            signals: [
                ReviewSignal(Fixture.movementDecided, in: Fixture.tripA, at: Fixture.now.addingTimeInterval(-60)),
                ReviewSignal(Fixture.movementDecided, in: Fixture.tripA, at: Fixture.now)
            ]
        )
        #expect(Fixture.decide(state: state) == .ask)
    }

    @Test("場面が数える種類を決めていれば、それ以外は数えない")
    func countedKindsFilter() {
        let state = ReviewState(
            installedAt: Fixture.eligibleState().installedAt,
            activeDays: Fixture.eligibleState().activeDays,
            signals: [ReviewSignal(Fixture.checkedIn, in: Fixture.tripB, at: Fixture.now)]
        )
        let moment = ReviewMoment(Fixture.nextTripPlanned, in: Fixture.tripB)
        #expect(Fixture.decide(moment, state: state) == .skip(.tooFewSignals(count: 0, required: 1)))
        #expect(Fixture.decide(moment, state: state.adding(
            ReviewSignal(Fixture.stayAdded, in: Fixture.tripB, at: Fixture.now))) == .ask)
    }

    @Test("範囲のある場面は、その範囲の合図だけを数える")
    func scopedMomentCountsOnlyItsScope() {
        let state = Fixture.eligibleState(scope: Fixture.tripB)
        #expect(Fixture.decide(ReviewMoment(Fixture.journalSaved, in: Fixture.tripA), state: state)
            == .skip(.tooFewSignals(count: 0, required: 2)))
        #expect(Fixture.decide(ReviewMoment(Fixture.journalSaved, in: Fixture.tripB), state: state) == .ask)
    }

    @Test("範囲の無い場面は、前に頼んだ後の合図だけを数える")
    func unscopedMomentCountsSinceLastAsk() {
        let asked = Fixture.now.addingTimeInterval(-Fixture.days(200))
        var state = Fixture.eligibleState(scope: nil)
        state.record(ReviewAsk(at: asked, version: AppVersion(major: 0, minor: 9), moment: Fixture.journalSaved))
        state.record(ReviewSignal(Fixture.movementDecided, at: asked.addingTimeInterval(-60)))
        #expect(Fixture.decide(ReviewMoment(Fixture.journalSaved), state: state) == .ask)

        var stale = ReviewState(installedAt: state.installedAt, activeDays: state.activeDays)
        stale.record(ReviewSignal(Fixture.movementDecided, at: asked.addingTimeInterval(-120)))
        stale.record(ReviewSignal(Fixture.stayAdded, at: asked.addingTimeInterval(-60)))
        stale.record(ReviewAsk(at: asked, version: AppVersion(major: 0, minor: 9), moment: Fixture.journalSaved))
        #expect(Fixture.decide(ReviewMoment(Fixture.journalSaved), state: stale)
            == .skip(.tooFewSignals(count: 0, required: 2)))
    }

    @Test("範囲の無い場面は、遡る日数より前の合図を数えない")
    func unscopedLookback() {
        let state = ReviewState(
            installedAt: Fixture.eligibleState().installedAt,
            activeDays: Fixture.eligibleState().activeDays,
            signals: [
                ReviewSignal(Fixture.movementDecided, at: Fixture.now.addingTimeInterval(-Fixture.days(20))),
                ReviewSignal(Fixture.stayAdded, at: Fixture.now.addingTimeInterval(-Fixture.days(1)))
            ]
        )
        let policy = Fixture.policy(unscopedSignalLookbackDays: 14)
        #expect(Fixture.decide(ReviewMoment(Fixture.journalSaved), state: state, policy: policy)
            == .skip(.tooFewSignals(count: 1, required: 2)))
        #expect(Fixture.decide(ReviewMoment(Fixture.journalSaved), state: state) == .ask)
    }

    @Test("これから先の時刻の合図は数えない")
    func futureSignalsDoNotCount() {
        let state = ReviewState(
            installedAt: Fixture.eligibleState().installedAt,
            activeDays: Fixture.eligibleState().activeDays,
            signals: [
                ReviewSignal(Fixture.movementDecided, in: Fixture.tripA, at: Fixture.now),
                ReviewSignal(Fixture.stayAdded, in: Fixture.tripA, at: Fixture.now.addingTimeInterval(60))
            ]
        )
        #expect(Fixture.decide(state: state) == .skip(.tooFewSignals(count: 1, required: 2)))
    }

    @Test("方針の既定の値は調べた値と同じ（7日・3日・版ごとに1回・120日・365日に3回）")
    func defaultsMatchTheResearch() {
        let policy = ReviewPolicy(timeZone: Fixture.tokyo, moments: [:])
        #expect(policy.isEnabled)
        #expect(policy.minimumDaysSinceInstall == 7)
        #expect(policy.minimumActiveDays == 3)
        #expect(policy.activeDayRetention == 60)
        #expect(policy.asksPerVersion == 1)
        #expect(policy.versionGranularity == .minor)
        #expect(policy.minimumDaysBetweenAsks == 120)
        #expect(policy.maximumAsksPerYear == ReviewPolicy.systemLimitPerYear)
        #expect(ReviewPolicy.systemLimitPerYear == 3)
        #expect(policy.asksPerScope == 1)
        #expect(policy.moments.isEmpty)
    }
}
