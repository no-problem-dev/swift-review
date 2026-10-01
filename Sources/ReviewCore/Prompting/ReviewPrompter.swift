import Foundation

/// The result of reaching a moment: the decision, and what the screen did with it.
public struct ReviewAttempt: Hashable, Sendable {
    public var decision: ReviewDecision
    /// `nil` unless the decision was ``ReviewDecision/ask``.
    public var outcome: ReviewAskOutcome?

    public init(decision: ReviewDecision, outcome: ReviewAskOutcome?) {
        self.decision = decision
        self.outcome = outcome
    }
}

/// Records what happens in the app and, at a declared moment, asks through the system if the rules
/// allow it.
///
/// This is the stateful shell around ``ReviewRules/decide(at:version:moment:state:policy:)``: it
/// loads state, stamps "now" from its clock, decides, hands an ask to the ``ReviewAsker``, records
/// the request if the system was called, and saves.
///
/// ```swift
/// let prompter = ReviewPrompter(
///     policy: policy,
///     version: AppVersion(bundle: .main) ?? AppVersion(major: 0),
///     store: UserDefaultsReviewStateStore(defaults: .standard),
///     asker: bridge
/// )
///
/// await prompter.markActive()                          // on launch and on every return to the foreground
/// await prompter.record(.movementDecided, in: tripScope)
/// await prompter.block(.paywallDismissed)
/// await prompter.reach(ReviewMoment(.journalSaved, in: tripScope))
/// ```
///
/// ## When state cannot be read
///
/// If the store throws, the prompter answers ``ReviewSkipReason/stateUnavailable``, records nothing
/// and **writes nothing**, so a state from a newer build survives a downgrade. The failure is
/// reported once per call as ``ReviewMetricEvent/stateUnavailable(_:)``.
public actor ReviewPrompter {

    private let policy: ReviewPolicy
    private let version: AppVersion
    private let store: any ReviewStateStore
    private let asker: any ReviewAsker
    private let clock: any ReviewClock
    private let metrics: any ReviewMetrics
    private var isAsking = false

    public init(
        policy: ReviewPolicy,
        version: AppVersion,
        store: any ReviewStateStore,
        asker: any ReviewAsker,
        clock: any ReviewClock = SystemReviewClock(),
        metrics: any ReviewMetrics = NoReviewMetrics()
    ) {
        self.policy = policy
        self.version = version
        self.store = store
        self.asker = asker
        self.clock = clock
        self.metrics = metrics
    }

    // MARK: - Recording

    /// Counts today as a day of use, and stamps the install time on the first call.
    ///
    /// Call it at launch and whenever the app returns to the foreground; repeats on the same day
    /// change nothing.
    public func markActive() {
        let now = clock.now()
        mutate { $0.markActive(at: now, in: policy.timeZone, retainingDays: policy.activeDayRetention) }
    }

    /// Counts one good outcome.
    public func record(_ kind: ReviewSignalKind, in scope: ReviewScope? = nil) {
        let now = clock.now()
        mutate { $0.record(ReviewSignal(kind, in: scope, at: now)) }
    }

    /// Takes back the most recent good outcome of this kind, for an action the person undid.
    public func retract(_ kind: ReviewSignalKind, in scope: ReviewScope? = nil) {
        mutate { $0.retract(kind, in: scope) }
    }

    /// Records something that holds requests back for its ``ReviewPolicy/cooldowns`` entry.
    public func block(_ kind: ReviewBlockerKind, in scope: ReviewScope? = nil) {
        let now = clock.now()
        mutate { $0.record(ReviewBlocker(kind, in: scope, at: now)) }
    }

    /// Drops a scope's signals and blockers, for a trip or document that was deleted.
    public func forget(_ scope: ReviewScope) {
        mutate { $0.forget(scope) }
    }

    /// Erases everything, as on account deletion. The next ``markActive()`` starts over as a fresh
    /// install.
    ///
    /// The system's own limit is not reset by this, so starting over never makes the system prompt
    /// more often than it allows.
    public func reset() {
        store.clear()
    }

    // MARK: - Deciding

    /// Decides without asking or recording anything except the metric.
    public func evaluate(_ moment: ReviewMoment) -> ReviewDecision {
        let decision = currentDecision(for: moment)
        metrics.record(.evaluated(moment, decision))
        return decision
    }

    /// Decides and, when the answer is ``ReviewDecision/ask``, hands the request to the asker and
    /// records it if the system was called.
    ///
    /// While one request waits for the screen, another moment is answered with
    /// ``ReviewSkipReason/askInProgress``.
    @discardableResult
    public func reach(_ moment: ReviewMoment) async -> ReviewAttempt {
        let decision = isAsking ? .skip(.askInProgress) : currentDecision(for: moment)
        metrics.record(.evaluated(moment, decision))
        guard decision == .ask else { return ReviewAttempt(decision: decision, outcome: nil) }

        isAsking = true
        let outcome = await asker.requestReview(for: moment)
        isAsking = false

        switch outcome {
        case .requested:
            let now = clock.now()
            var ordinal = 0
            mutate { state in
                state.record(ReviewAsk(at: now, version: version, moment: moment.name, scope: moment.scope))
                ordinal = state.asks.count
            }
            metrics.record(.requested(moment, version: version, ordinal: ordinal))
        case let .abandoned(reason):
            metrics.record(.abandoned(moment, reason))
        }
        return ReviewAttempt(decision: decision, outcome: outcome)
    }

    /// The stored state, for a developer screen.
    public func state() throws(ReviewStoreError) -> ReviewState? {
        try store.load()
    }

    // MARK: - Private

    private func currentDecision(for moment: ReviewMoment) -> ReviewDecision {
        let state: ReviewState
        do {
            state = try store.load() ?? ReviewState()
        } catch {
            metrics.record(.stateUnavailable(error))
            return .skip(.stateUnavailable)
        }
        return ReviewRules.decide(at: clock.now(), version: version, moment: moment, state: state, policy: policy)
    }

    private func mutate(_ change: (inout ReviewState) -> Void) {
        do {
            var state = try store.load() ?? ReviewState()
            change(&state)
            state.prune(at: clock.now(), policy: policy)
            try store.save(state)
        } catch {
            metrics.record(.stateUnavailable(error))
        }
    }
}
