import Foundation
import Testing
import ReviewCore

@Suite("止める出来事: いまの条件と、記録した出来事の期間")
struct BlockerRuleTests {

    @Test("オフラインのように、いま続いている条件があれば頼まない。前提は満たしている")
    func ongoingCondition() {
        let decision = Fixture.decide(ReviewMoment(Fixture.journalSaved, in: Fixture.tripA, ongoing: [Fixture.offline]))
        #expect(decision == .skip(.ongoing(Fixture.offline)))
        #expect(decision.passedPrerequisites)
    }

    @Test("いまの条件が2つあれば、名前の順で先のものを返す")
    func ongoingConditionsAreReportedInNameOrder() {
        let decision = Fixture.decide(ReviewMoment(Fixture.journalSaved, in: Fixture.tripA,
                                                   ongoing: [Fixture.sheetShown, Fixture.offline]))
        #expect(decision == .skip(.ongoing(Fixture.offline)))
    }

    struct Window: Sendable, CustomTestStringConvertible {
        let kind: ReviewBlockerKind
        let days: Int
        var testDescription: String { "\(kind.rawValue) \(days)日" }
    }

    @Test(
        "出来事の期間の最後の1時間は頼まず、期間を過ぎたら頼む",
        arguments: [
            Window(kind: Fixture.paywallDismissed, days: 14),
            Window(kind: Fixture.error, days: 3),
            Window(kind: Fixture.syncReverted, days: 3),
            Window(kind: Fixture.feedbackSent, days: 30),
            Window(kind: Fixture.cancelScreen, days: 90)
        ]
    )
    func cooldownBoundary(window: Window) {
        let blockedAt = Fixture.now.addingTimeInterval(-Fixture.days(Double(window.days)) + 3_600)
        let state = Fixture.eligibleState().adding(ReviewBlocker(window.kind, at: blockedAt))
        let until = blockedAt.addingTimeInterval(Fixture.days(Double(window.days)))
        #expect(Fixture.decide(state: state) == .skip(.coolingDown(window.kind, until: until)))
        #expect(Fixture.decide(state: state, at: until) == .ask)
    }

    @Test("範囲を保つ出来事は、その範囲では日数を過ぎても止め、ほかの範囲では日数だけ止める")
    func scopeHoldingBlocker() {
        let disruptedAt = Fixture.now.addingTimeInterval(-Fixture.days(1))
        let state = Fixture.eligibleState(scope: Fixture.tripA)
            .adding(ReviewSignal(Fixture.movementDecided, in: Fixture.tripB, at: Fixture.now))
            .adding(ReviewBlocker(Fixture.tripDisrupted, in: Fixture.tripA, at: disruptedAt))
        let sameTrip = ReviewMoment(Fixture.journalSaved, in: Fixture.tripA)
        let nextTrip = ReviewMoment(Fixture.nextTripPlanned, in: Fixture.tripB)

        #expect(Fixture.decide(sameTrip, state: state) == .skip(.coolingDown(Fixture.tripDisrupted, until: nil)))
        let later = Fixture.now.addingTimeInterval(Fixture.days(100))
        #expect(Fixture.decide(sameTrip, state: state, at: later) == .skip(.coolingDown(Fixture.tripDisrupted, until: nil)))

        let threeDays = disruptedAt.addingTimeInterval(Fixture.days(3))
        #expect(Fixture.decide(nextTrip, state: state) == .skip(.coolingDown(Fixture.tripDisrupted, until: threeDays)))
        #expect(Fixture.decide(nextTrip, state: state, at: threeDays) == .ask)
    }

    @Test("範囲で記録した出来事でも、範囲を保たない期間なら全体を日数だけ止める")
    func scopedBlockerWithoutHoldAppliesEverywhere() {
        let state = Fixture.eligibleState(scope: Fixture.tripB)
            .adding(ReviewBlocker(Fixture.error, in: Fixture.tripA, at: Fixture.now.addingTimeInterval(-3_600)))
        #expect(Fixture.decide(ReviewMoment(Fixture.journalSaved, in: Fixture.tripB), state: state)
            == .skip(.coolingDown(Fixture.error, until: Fixture.now.addingTimeInterval(Fixture.days(3) - 3_600))))
    }

    @Test("範囲を保つ出来事を範囲なしで記録したら、日数だけ止める")
    func holdWithoutScopeIsJustDays() {
        let state = Fixture.eligibleState()
            .adding(ReviewBlocker(Fixture.tripDisrupted, at: Fixture.now.addingTimeInterval(-Fixture.days(4))))
        #expect(Fixture.decide(state: state) == .ask)
    }

    @Test("方針に期間の無い出来事は止めない")
    func blockerWithoutCooldownHoldsNothing() {
        let state = Fixture.eligibleState().adding(ReviewBlocker("unknown_kind", at: Fixture.now))
        #expect(Fixture.decide(state: state) == .ask)
    }

    @Test("いくつも当たれば、最も長く止めるものを返す")
    func longestHoldIsReported() {
        let state = Fixture.eligibleState()
            .adding(ReviewBlocker(Fixture.error, at: Fixture.now.addingTimeInterval(-3_600)))
            .adding(ReviewBlocker(Fixture.paywallDismissed, at: Fixture.now.addingTimeInterval(-Fixture.days(10))))
        let until = Fixture.now.addingTimeInterval(-Fixture.days(10) + Fixture.days(14))
        #expect(Fixture.decide(state: state) == .skip(.coolingDown(Fixture.paywallDismissed, until: until)))
    }

    @Test("同じ種類の出来事は、最後の時刻から期間を数える")
    func cooldownRunsFromTheLatestOccurrence() {
        let state = Fixture.eligibleState()
            .adding(ReviewBlocker(Fixture.error, at: Fixture.now.addingTimeInterval(-Fixture.days(1))))
            .adding(ReviewBlocker(Fixture.error, at: Fixture.now.addingTimeInterval(-Fixture.days(10))))
        let until = Fixture.now.addingTimeInterval(Fixture.days(2))
        #expect(Fixture.decide(state: state) == .skip(.coolingDown(Fixture.error, until: until)))
    }
}

@Suite("上限: 版ごと・範囲ごと・間の日数・365日の回数")
struct LimitRuleTests {

    private func asked(_ daysAgo: Double, _ version: AppVersion, in scope: ReviewScope? = nil) -> ReviewAsk {
        ReviewAsk(at: Fixture.now.addingTimeInterval(-Fixture.days(daysAgo)), version: version,
                  moment: Fixture.journalSaved, scope: scope)
    }

    @Test("同じ版では2回目を頼まない")
    func oncePerVersion() {
        let state = Fixture.eligibleState().adding(asked(200, Fixture.v1_0))
        #expect(Fixture.decide(state: state) == .skip(.alreadyAskedThisVersion(Fixture.v1_0)))
    }

    @Test("修正だけの版（z だけが変わる）では頼み直さず、x.y が変われば頼む")
    func fixReleaseDoesNotEarnAnotherRequest() {
        let state = Fixture.eligibleState().adding(asked(200, Fixture.v1_0))
        #expect(Fixture.decide(state: state, version: Fixture.v1_0_1)
            == .skip(.alreadyAskedThisVersion(Fixture.v1_0)))
        #expect(Fixture.decide(state: state, version: Fixture.v1_1) == .ask)
    }

    @Test("版の単位を patch にすれば、修正の版でも頼む")
    func patchGranularity() {
        let state = Fixture.eligibleState().adding(asked(200, Fixture.v1_0))
        #expect(Fixture.decide(state: state, version: Fixture.v1_0_1,
                               policy: Fixture.policy(versionGranularity: .patch)) == .ask)
    }

    @Test("同じ範囲では2回目を頼まない（記録の後の割り勘の済みは、同じ旅行なら頼まない）")
    func oncePerScope() {
        let state = Fixture.eligibleState().adding(asked(200, Fixture.v1_0, in: Fixture.tripA))
        let moment = ReviewMoment(Fixture.splitSettled, in: Fixture.tripA)
        #expect(Fixture.decide(moment, state: state, version: Fixture.v1_1)
            == .skip(.alreadyAskedInScope(Fixture.tripA)))
    }

    @Test("前に頼んでから119日は頼まず、120日で頼む")
    func minimumIntervalBoundary() {
        let state = Fixture.eligibleState().adding(asked(119, Fixture.v1_0, in: Fixture.tripB))
        let until = Fixture.now.addingTimeInterval(Fixture.days(1))
        #expect(Fixture.decide(state: state, version: Fixture.v1_1) == .skip(.tooSoonAfterLastAsk(until: until)))
        #expect(Fixture.decide(state: state, at: until, version: Fixture.v1_1) == .ask)
    }

    @Test("365日で3回まで。出たかは分からないので、呼んだ回をすべて数える")
    func yearlyCapCountsEveryCall() {
        let state = Fixture.eligibleState()
            .adding(asked(360, AppVersion(major: 0, minor: 7)))
            .adding(asked(240, AppVersion(major: 0, minor: 8)))
            .adding(asked(120, AppVersion(major: 0, minor: 9)))
        let until = Fixture.now.addingTimeInterval(Fixture.days(5))
        #expect(Fixture.decide(state: state) == .skip(.yearlyLimitReached(until: until)))
        #expect(Fixture.decide(state: state, at: until) == .ask)
    }

    @Test("365日より前に頼んだ回は、年の上限に数えない")
    func asksOutsideTheWindowDoNotCount() {
        let state = Fixture.eligibleState()
            .adding(asked(400, AppVersion(major: 0, minor: 6)))
            .adding(asked(240, AppVersion(major: 0, minor: 8)))
            .adding(asked(120, AppVersion(major: 0, minor: 9)))
        #expect(Fixture.decide(state: state) == .ask)
    }

    @Test("年の上限を0にすれば頼まない")
    func zeroYearlyLimit() {
        #expect(Fixture.decide(policy: Fixture.policy(maximumAsksPerYear: 0))
            == .skip(.yearlyLimitReached(until: .distantFuture)))
    }

    @Test("理由は 前提 → 止める出来事 → 上限 の順で、最初に当たったものを返す")
    func reasonsComeInStageOrder() {
        let everythingWrong = Fixture.eligibleState()
            .adding(ReviewBlocker(Fixture.paywallDismissed, at: Fixture.now))
            .adding(asked(1, Fixture.v1_0, in: Fixture.tripA))
        let notYet = ReviewMoment(Fixture.journalSaved, in: Fixture.tripA, unmet: [Fixture.hasOwnTrip])
        #expect(Fixture.decide(notYet, state: everythingWrong) == .skip(.requirementUnmet(Fixture.hasOwnTrip)))

        let reached = ReviewMoment(Fixture.journalSaved, in: Fixture.tripA)
        let blocked = Fixture.decide(reached, state: everythingWrong)
        #expect(blocked == .skip(.coolingDown(Fixture.paywallDismissed,
                                              until: Fixture.now.addingTimeInterval(Fixture.days(14)))))

        let limited = Fixture.decide(reached, state: everythingWrong, at: Fixture.now.addingTimeInterval(Fixture.days(15)))
        #expect(limited == .skip(.alreadyAskedThisVersion(Fixture.v1_0)))
    }

    @Test("理由ごとの段と、計測に出す名前")
    func stagesAndCodes() {
        #expect(ReviewSkipReason.tooFewSignals(count: 0, required: 2).stage == .prerequisite)
        #expect(ReviewSkipReason.coolingDown(Fixture.paywallDismissed, until: nil).stage == .blocker)
        #expect(ReviewSkipReason.yearlyLimitReached(until: Fixture.now).stage == .limit)
        #expect(ReviewSkipReason.askInProgress.stage == .limit)
        #expect(ReviewSkipReason.coolingDown(Fixture.paywallDismissed, until: nil).code == "paywall_dismissed")
        #expect(ReviewSkipReason.ongoing(Fixture.offline).code == "offline")
        #expect(ReviewSkipReason.alreadyAskedThisVersion(Fixture.v1_0).code == "already_asked_this_version")
    }
}
