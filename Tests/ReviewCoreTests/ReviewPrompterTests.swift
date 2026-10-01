import Foundation
import Testing
import ReviewCore
import ReviewTesting

@Suite("頼む流れ: 記録 → 判定 → 頼む口 → 記録")
struct ReviewPrompterTests {

    struct Harness {
        let clock = ManualReviewClock(Fixture.date(2026, 9, 1, 9))
        let store = InMemoryReviewStateStore()
        let asker = RecordingReviewAsker()
        let metrics = RecordingReviewMetrics()

        func prompter(version: AppVersion = Fixture.v1_0, store: (any ReviewStateStore)? = nil) -> ReviewPrompter {
            ReviewPrompter(policy: Fixture.policy(), version: version, store: store ?? self.store,
                           asker: asker, clock: clock, metrics: metrics)
        }

        /// Opens the app on `days` separate days, one a day.
        func use(_ prompter: ReviewPrompter, days: Int) async {
            for _ in 0..<days {
                await prompter.markActive()
                clock.advance(days: 1)
            }
        }
    }

    private let journal = ReviewMoment(Fixture.journalSaved, in: Fixture.tripA)

    @Test("条件がそろうまでは頼まず、そろった場面で1回だけ頼む")
    func asksOnceWhenReady() async {
        let h = Harness()
        let prompter = h.prompter()

        await h.use(prompter, days: 3)
        await prompter.record(Fixture.movementDecided, in: Fixture.tripA)
        await prompter.record(Fixture.stayAdded, in: Fixture.tripA)
        let early = await prompter.reach(journal)
        #expect(early.decision == .skip(.tooSoonAfterInstall(days: 3, required: 7)))
        #expect(h.asker.count == 0)

        h.clock.advance(days: 4)
        let ready = await prompter.reach(journal)
        #expect(ready == ReviewAttempt(decision: .ask, outcome: .requested))
        #expect(h.asker.moments == [journal])

        let again = await prompter.reach(journal)
        #expect(again.decision == .skip(.alreadyAskedThisVersion(Fixture.v1_0)))
        #expect(h.asker.count == 1)
    }

    @Test("呼んだ回を記録する（何回目か・版・場面・範囲）")
    func recordsTheRequest() async throws {
        let h = Harness()
        try await ready(h)
        let prompter = h.prompter()
        await prompter.reach(journal)

        let state = try #require(try h.store.load())
        #expect(state.asks == [ReviewAsk(at: h.clock.now(), version: Fixture.v1_0, moment: Fixture.journalSaved,
                                         scope: Fixture.tripA)])
        #expect(h.metrics.events.last == .requested(journal, version: Fixture.v1_0, ordinal: 1))
    }

    @Test("画面が取りやめた回は数えず、次の場面でまた頼める")
    func abandonedIsNotCounted() async throws {
        let h = Harness()
        try await ready(h)
        h.asker.answer(.abandoned(.obstructed))
        let prompter = h.prompter()

        let first = await prompter.reach(journal)
        #expect(first == ReviewAttempt(decision: .ask, outcome: .abandoned(.obstructed)))
        #expect(try h.store.load()?.asks.isEmpty == true)
        #expect(h.metrics.events.last == .abandoned(journal, .obstructed))

        h.asker.answer(.requested)
        let second = await prompter.reach(journal)
        #expect(second.outcome == .requested)
        #expect(h.asker.count == 2)
    }

    @Test("頼む口が待っている間の別の場面は頼まない")
    func secondMomentWhileWaiting() async throws {
        let h = Harness()
        try await ready(h)
        let gate = GateAsker()
        let prompter = ReviewPrompter(policy: Fixture.policy(), version: Fixture.v1_0, store: h.store,
                                      asker: gate, clock: h.clock, metrics: h.metrics)

        async let first = prompter.reach(journal)
        await gate.waitUntilCalled()
        let second = await prompter.reach(ReviewMoment(Fixture.splitSettled, in: Fixture.tripA))
        #expect(second.decision == .skip(.askInProgress))
        await gate.open(with: .requested)
        #expect(await first.outcome == .requested)
    }

    @Test("取り消した操作は合図に数えない")
    func retractedSignalsDoNotCount() async throws {
        let h = Harness()
        let prompter = h.prompter()
        await h.use(prompter, days: 3)
        h.clock.advance(days: 7)
        await prompter.record(Fixture.movementDecided, in: Fixture.tripA)
        await prompter.record(Fixture.stayAdded, in: Fixture.tripA)
        await prompter.retract(Fixture.stayAdded, in: Fixture.tripA)

        let attempt = await prompter.reach(journal)
        #expect(attempt.decision == .skip(.tooFewSignals(count: 1, required: 2)))
    }

    @Test("ペイウォールを閉じた後の14日は頼まない")
    func blockerThroughThePrompter() async throws {
        let h = Harness()
        try await ready(h)
        let prompter = h.prompter()
        await prompter.block(Fixture.paywallDismissed)
        #expect(await prompter.reach(journal).decision.passedPrerequisites)
        #expect(h.asker.count == 0)

        h.clock.advance(days: 14)
        #expect(await prompter.reach(journal).outcome == .requested)
    }

    @Test("範囲を忘れると、その範囲の合図は数えない")
    func forgottenScope() async throws {
        let h = Harness()
        try await ready(h)
        let prompter = h.prompter()
        await prompter.forget(Fixture.tripA)
        #expect(await prompter.reach(journal).decision == .skip(.tooFewSignals(count: 0, required: 2)))
    }

    @Test("アカウントの削除で全部を消し、インストールからやり直す")
    func resetStartsOver() async throws {
        let h = Harness()
        try await ready(h)
        let prompter = h.prompter()
        await prompter.reach(journal)

        await prompter.reset()
        #expect(try h.store.load() == nil)

        await prompter.markActive()
        let state = try #require(try h.store.load())
        #expect(state.installedAt == h.clock.now())
        #expect(state.activeDays.count == 1)
        #expect(state.asks.isEmpty)
        #expect(state.signals.isEmpty)
        #expect(await prompter.reach(journal).decision == .skip(.tooSoonAfterInstall(days: 0, required: 7)))
    }

    @Test("新しい版が書いた状態は読まず、書き換えもしない")
    func newerSchemaIsLeftAlone() async throws {
        let h = Harness()
        let newer = Data(#"{"schema": 9, "somethingNew": true}"#.utf8)
        let store = InMemoryReviewStateStore(storedData: newer)
        let prompter = h.prompter(store: store)

        await prompter.markActive()
        await prompter.record(Fixture.movementDecided, in: Fixture.tripA)
        let attempt = await prompter.reach(journal)

        #expect(attempt.decision == .skip(.stateUnavailable))
        #expect(store.storedData == newer)
        #expect(h.asker.count == 0)
        #expect(h.metrics.events.contains(.stateUnavailable(.newerSchema(found: 9, supported: 1))))
    }

    @Test("evaluate は判定と計測だけで、頼む口を呼ばず何も記録しない")
    func evaluateHasNoSideEffects() async throws {
        let h = Harness()
        try await ready(h)
        let before = try h.store.load()
        let prompter = h.prompter()

        #expect(await prompter.evaluate(journal) == .ask)
        #expect(h.asker.count == 0)
        #expect(try h.store.load() == before)
        #expect(h.metrics.events == [.evaluated(journal, .ask)])
    }

    @Test("計測の印は、判定 → 頼んだ の順で出し、範囲の ID と本人の文は載せない")
    func metricsOrderAndParameters() async throws {
        let h = Harness()
        try await ready(h)
        let prompter = h.prompter()
        await prompter.reach(journal)

        #expect(h.metrics.names == ["review_prompt_evaluated", "review_prompt_requested"])
        let evaluated = h.metrics.events[0].parameters
        #expect(evaluated["moment"] == .text("journal_saved"))
        #expect(evaluated["eligible"] == .flag(true))
        #expect(evaluated["asked"] == .flag(true))
        let requested = h.metrics.events[1].parameters
        #expect(requested == ["moment": .text("journal_saved"), "app_version": .text("1.0.0"), "nth": .count(1)])
        let values = h.metrics.events.flatMap { $0.parameters.values.map(\.description) }
        #expect(!values.contains(Fixture.tripA.rawValue))
    }

    @Test("前提で止まった判定は、計測で eligible を false にする")
    func ineligibleMetric() async {
        let h = Harness()
        let prompter = h.prompter()
        await prompter.reach(journal)
        let parameters = h.metrics.events[0].parameters
        #expect(parameters["eligible"] == .flag(false))
        #expect(parameters["stage"] == .text("prerequisite"))
        #expect(parameters["reason"] == .text("too_soon_after_install"))
    }

    @Test("新しい x.y の版で、120日を過ぎ、直近60日に3日開いていれば、また頼む")
    func asksAgainInANewVersion() async throws {
        let h = Harness()
        try await ready(h)
        await h.prompter(version: Fixture.v1_0).reach(journal)

        let tripB = ReviewMoment(Fixture.journalSaved, in: Fixture.tripB)
        let next = h.prompter(version: Fixture.v1_1)
        await next.record(Fixture.movementDecided, in: Fixture.tripB)
        await next.record(Fixture.stayAdded, in: Fixture.tripB)
        h.clock.advance(days: 116)
        await next.markActive()
        #expect(await next.reach(tripB).decision == .skip(.tooFewActiveDays(count: 1, required: 3)))

        await h.use(next, days: 3)
        #expect(await next.reach(tripB).decision.passedPrerequisites)
        #expect(h.asker.count == 1)

        h.clock.advance(days: 1)
        #expect(await next.reach(tripB).outcome == .requested)
        #expect(h.metrics.events.last == .requested(tripB, version: Fixture.v1_1, ordinal: 2))
    }

    /// Ten days of use over ten days, then two signals in trip A.
    private func ready(_ h: Harness) async throws {
        let prompter = h.prompter()
        await h.use(prompter, days: 10)
        await prompter.record(Fixture.movementDecided, in: Fixture.tripA)
        await prompter.record(Fixture.stayAdded, in: Fixture.tripA)
        h.metrics.reset()
    }
}

/// An asker that holds the request until the test opens it.
private actor GateAsker: ReviewAsker {
    private var called: CheckedContinuation<Void, Never>?
    private var wasCalled = false
    private var pending: CheckedContinuation<ReviewAskOutcome, Never>?

    func requestReview(for moment: ReviewMoment) async -> ReviewAskOutcome {
        wasCalled = true
        called?.resume()
        called = nil
        return await withCheckedContinuation { pending = $0 }
    }

    func waitUntilCalled() async {
        guard !wasCalled else { return }
        await withCheckedContinuation { called = $0 }
    }

    func open(with outcome: ReviewAskOutcome) {
        pending?.resume(returning: outcome)
        pending = nil
    }
}
