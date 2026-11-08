import Foundation
import Testing
import ReviewCore
import ReviewTesting

@Suite("アプリ自前の画面の瞬間: OS の枠を使わず、版ごとに1回と「星をつける」の後の日数だけを持つ")
struct ScreenMomentTests {

    private let screen = ReviewScreenMoment(.afterWhatsNew)

    private func policy(daysAfterRated: Int = 120) -> ReviewPolicy {
        ReviewPolicy(timeZone: Fixture.tokyo, screens: [.afterWhatsNew: ReviewScreenRule(daysAfterRated: daysAfterRated)])
    }

    /// Installed long enough ago, unless a test says otherwise.
    private static let longAgo = Fixture.now.addingTimeInterval(-Fixture.days(30))

    private func decide(
        _ state: ReviewState = ReviewState(), at now: Date = Fixture.now, version: AppVersion = Fixture.v1_0,
        policy: ReviewPolicy? = nil, screen: ReviewScreenMoment? = nil
    ) -> ReviewDecision {
        var state = state
        if state.installedAt == nil { state.installedAt = Self.longAgo }
        return ReviewRules.decide(at: now, version: version, screen: screen ?? self.screen, state: state,
                                  policy: policy ?? self.policy())
    }

    @Test("インストールから7日（方針の値）たつまで出さない。画面ごとに変えられ、0 で見ない")
    func waitsDaysSinceInstall() {
        let installed = ReviewState(installedAt: Fixture.now.addingTimeInterval(-Fixture.days(6)))
        #expect(decide(installed) == .skip(.tooSoonAfterInstall(days: 6, required: 7)))
        #expect(!decide(installed).passedPrerequisites)
        #expect(decide(installed, at: Fixture.now.addingTimeInterval(Fixture.days(1))) == .ask)

        var stricter = policy()
        stricter.minimumDaysSinceInstall = 14
        #expect(decide(ReviewState(installedAt: Self.longAgo.addingTimeInterval(Fixture.days(20))), policy: stricter)
                == .skip(.tooSoonAfterInstall(days: 10, required: 14)))

        let own = ReviewPolicy(timeZone: Fixture.tokyo,
                               screens: [.afterWhatsNew: ReviewScreenRule(minimumDaysSinceInstall: 2)])
        #expect(decide(installed, policy: own) == .ask)
        let off = ReviewPolicy(timeZone: Fixture.tokyo,
                               screens: [.afterWhatsNew: ReviewScreenRule(minimumDaysSinceInstall: 0)])
        #expect(ReviewRules.decide(at: Fixture.now, version: Fixture.v1_0, screen: screen,
                                   state: ReviewState(installedAt: Fixture.now), policy: off) == .ask)
        #expect(ReviewRules.decide(at: Fixture.now, version: Fixture.v1_0, screen: screen,
                                   state: ReviewState(), policy: policy())
                == .skip(.tooSoonAfterInstall(days: 0, required: 7)))
    }

    @Test("アプリの前提（得を受け取ったか）が揃わないうちは出さない")
    func unmetRequirementHolds() {
        let moment = ReviewScreenMoment(.afterWhatsNew, unmet: [Fixture.hasOwnTrip])
        #expect(decide(screen: moment) == .skip(.requirementUnmet(Fixture.hasOwnTrip)))
        #expect(!decide(screen: moment).passedPrerequisites)
    }

    @Test("開いた日・合図・前に頼んだ日・365日の回数に関わらず出せる")
    func ignoresTheSystemAllowanceRules() {
        let asked = ReviewState(
            installedAt: Self.longAgo,
            asks: [ReviewAsk(at: Fixture.now.addingTimeInterval(-Fixture.days(1)), version: Fixture.v1_0,
                             moment: "book_completed")]
        )
        #expect(decide(asked) == .ask)
    }

    @Test("宣言していない名前・止めた方針では出さない。OS の場面に宣言しただけでは出さない")
    func needsAScreenDeclaration() {
        #expect(decide(policy: ReviewPolicy(timeZone: Fixture.tokyo)) == .skip(.undeclaredMoment(.afterWhatsNew)))
        let systemOnly = ReviewPolicy(timeZone: Fixture.tokyo, moments: [.afterWhatsNew: ReviewMomentRule()])
        #expect(decide(policy: systemOnly) == .skip(.undeclaredMoment(.afterWhatsNew)))
        var off = policy()
        off.isEnabled = false
        #expect(decide(policy: off) == .skip(.disabled))
    }

    @Test("ペイウォールを閉じて14日・エラーから3日は出さない（R25）。いまの条件でも出さない")
    func blockersHoldTheScreenBack() {
        let paywall = ReviewState().adding(ReviewBlocker(.paywallDismissed, at: Fixture.now.addingTimeInterval(-Fixture.days(13))))
        #expect(decide(paywall) == .skip(.coolingDown(.paywallDismissed,
                                                     until: Fixture.now.addingTimeInterval(Fixture.days(1)))))
        #expect(decide(paywall, at: Fixture.now.addingTimeInterval(Fixture.days(1))) == .ask)
        let error = ReviewState().adding(ReviewBlocker(.error, at: Fixture.now.addingTimeInterval(-Fixture.days(2))))
        #expect(decide(error).passedPrerequisites)
        #expect(decide(error) != .ask)
        let purchased = ReviewScreenMoment(.afterWhatsNew, ongoing: [.purchased])
        #expect(decide(screen: purchased) == .skip(.ongoing(.purchased)))
    }

    @Test("同じ x.y では1回。直しだけの版では出さず、次の x.y でまた出す")
    func oncePerVersion() {
        let shown = ReviewState(screenShows: [ReviewScreenShow(at: Fixture.now, version: Fixture.v1_0, moment: .afterWhatsNew)])
        #expect(decide(shown, version: Fixture.v1_0_1) == .skip(.alreadyShownThisVersion(Fixture.v1_0)))
        #expect(decide(shown, version: Fixture.v1_1) == .ask)
    }

    @Test("「星をつける」を押してから120日は、新しい版でも出さない")
    func waitsAfterRated() {
        let rated = ReviewState(ratedAt: Fixture.now)
        let day119 = Fixture.now.addingTimeInterval(Fixture.days(119))
        #expect(decide(rated, at: day119, version: Fixture.v1_1)
                == .skip(.ratedRecently(until: Fixture.now.addingTimeInterval(Fixture.days(120)))))
        #expect(decide(rated, at: day119.addingTimeInterval(Fixture.days(1)), version: Fixture.v1_1) == .ask)
    }

    @Test("「星をつける」の印は OS の場面には効かない")
    func ratedDoesNotHoldTheSystemPrompt() {
        var state = Fixture.eligibleState()
        state.ratedAt = Fixture.now
        #expect(Fixture.decide(state: state) == .ask)
    }

    @Test("prompter: 出すと決めたら出した記録を残し、OS は呼ばず、頼んだ回にも数えない")
    func prompterPresents() async throws {
        let clock = ManualReviewClock(Fixture.now)
        let store = InMemoryReviewStateStore()
        let asker = RecordingReviewAsker()
        let metrics = RecordingReviewMetrics()
        let prompter = ReviewPrompter(policy: policy(), version: Fixture.v1_0, store: store, asker: asker,
                                      clock: clock, metrics: metrics)
        await prompter.markActive()
        #expect(await prompter.present(screen) == .skip(.tooSoonAfterInstall(days: 0, required: 7)))
        await prompter.backdateInstall(to: Self.longAgo)
        await prompter.backdateInstall(to: Fixture.now)
        #expect(try store.load()?.installedAt == Self.longAgo)

        #expect(await prompter.present(screen) == .ask)
        #expect(await prompter.present(screen) == .skip(.alreadyShownThisVersion(Fixture.v1_0)))
        #expect(asker.count == 0)

        let state = try #require(try store.load())
        #expect(state.asks.isEmpty)
        #expect(state.screenShows == [ReviewScreenShow(at: Fixture.now, version: Fixture.v1_0, moment: .afterWhatsNew)])
        #expect(metrics.names == ["review_screen_evaluated", "review_screen_evaluated", "review_screen_shown",
                                  "review_screen_evaluated"])
        #expect(!metrics.events.contains { $0.isInCommonCatalog })

        await prompter.markRated()
        #expect(try store.load()?.ratedAt == Fixture.now)
    }
}

@Suite("起動から30秒（R9）")
struct LaunchRuleTests {

    @Test("起動から30秒たつまでは止める出来事として頼まず、30秒で頼む")
    func waitsAfterLaunch() async {
        let clock = ManualReviewClock(Fixture.now.addingTimeInterval(-Fixture.days(30)))
        let store = InMemoryReviewStateStore()
        let asker = RecordingReviewAsker()
        let policy = ReviewPolicy(timeZone: Fixture.tokyo, moments: [Fixture.journalSaved: ReviewMomentRule(minimumSignals: 1)])
        let first = ReviewPrompter(policy: policy, version: Fixture.v1_0, store: store, asker: asker, clock: clock)
        await first.markActive()
        await first.record(Fixture.movementDecided)
        clock.set(Fixture.now)

        let relaunched = ReviewPrompter(policy: policy, version: Fixture.v1_0, store: store, asker: asker, clock: clock)
        await relaunched.markActive()
        clock.advance(seconds: 29)
        let early = await relaunched.reach(ReviewMoment(Fixture.journalSaved))
        #expect(early.decision == .skip(.tooSoonAfterLaunch(until: Fixture.now.addingTimeInterval(30))))
        #expect(early.decision.passedPrerequisites)

        clock.advance(seconds: 1)
        #expect(await relaunched.reach(ReviewMoment(Fixture.journalSaved)).outcome == .requested)
    }

    @Test("純粋な判定は launchedAt を渡さなければこの規則を見ない")
    func pureDecisionWithoutLaunch() {
        var policy = Fixture.policy()
        policy.minimumSecondsSinceLaunch = 30
        let state = Fixture.eligibleState()
        let moment = ReviewMoment(Fixture.journalSaved, in: Fixture.tripA)
        #expect(ReviewRules.decide(at: Fixture.now, version: Fixture.v1_0, moment: moment, state: state, policy: policy) == .ask)
        #expect(ReviewRules.decide(at: Fixture.now, version: Fixture.v1_0, moment: moment, state: state, policy: policy,
                                   launchedAt: Fixture.now.addingTimeInterval(-10)) != .ask)
    }
}

@Suite("0.2 で足した物: 状態の形・計測の口・版")
struct AdditionsTests {

    @Test("出した記録と星の印は保存して読み戻せ、0.1 の形（どちらも無い）も読める")
    func stateRoundTrip() throws {
        let state = ReviewState(
            screenShows: [ReviewScreenShow(at: Fixture.now, version: Fixture.v1_1, moment: .afterWhatsNew)],
            ratedAt: Fixture.now
        )
        #expect(try ReviewState.decode(state.encoded()) == state)
        let old = Data(#"{"schema": 1, "activeDays": [], "signals": [], "blockers": [], "asks": []}"#.utf8)
        let decoded = try ReviewState.decode(old)
        #expect(decoded.screenShows.isEmpty)
        #expect(decoded.ratedAt == nil)
        let object = try JSONSerialization.jsonObject(with: ReviewState().encoded()) as? [String: Any]
        #expect(object?["screenShows"] == nil)
    }

    @Test("クロージャの口は全部の出来事を渡す")
    func handlerForwards() {
        let seen = RecordingReviewMetrics()
        let metrics = ReviewMetricsHandler { seen.record($0) }
        metrics.record(.requested(ReviewMoment(.afterWhatsNew), ordinal: 1))
        #expect(seen.names == ["review_requested"])
        #expect(seen.events[0].parameters == ["moment": .text("after_whats_new")])
    }

    @Test("版は部分の数が違っても同じ版として比べ、単位で同じかを答える")
    func versionComparison() throws {
        let short = try #require(AppVersion("1.6"))
        #expect(short == AppVersion(major: 1, minor: 6, patch: 0))
        #expect(try #require(AppVersion("1.10.0")) > short)
        #expect(short.isSame(as: AppVersion(major: 1, minor: 6, patch: 3), at: .minor))
        #expect(!short.isSame(as: AppVersion(major: 1, minor: 6, patch: 3), at: .patch))
        #expect(AppVersion("1.6.0-beta") == nil)
    }
}
