import Foundation

/// The decision, as a pure function of its arguments.
///
/// Nothing here reads a clock, a time zone, a store or the bundle: "now", the version, the moment,
/// the state and the policy all arrive as arguments. The same arguments always give the same
/// answer, so every rule is pinned by a unit test with no waiting and no device.
public enum ReviewRules {

    /// Decides whether `moment` may call the system's review request.
    ///
    /// Rules are checked in a fixed order and the first that fails is returned:
    ///
    /// 1. **Prerequisites** — enabled, moment declared, days since install, days of use,
    ///    app requirements, signals
    /// 2. **Blockers** — conditions in effect now, then recorded blockers still cooling down
    /// 3. **Limits** — once per version, once per scope, days since the last request, the rolling
    ///    365-day cap
    ///
    /// Prerequisites come first so that ``ReviewDecision/passedPrerequisites`` separates "not yet"
    /// from "not now" for metrics.
    ///
    /// - Parameters:
    ///   - now: The current instant
    ///   - version: The running app's version
    ///   - moment: Where the app is, and what holds right now
    ///   - state: What has been recorded on this device
    ///   - policy: The thresholds
    public static func decide(
        at now: Date,
        version: AppVersion,
        moment: ReviewMoment,
        state: ReviewState,
        policy: ReviewPolicy
    ) -> ReviewDecision {
        if let reason = prerequisiteFailure(at: now, moment: moment, state: state, policy: policy)
            ?? blockerFailure(at: now, moment: moment, state: state, policy: policy)
            ?? limitFailure(at: now, version: version, moment: moment, state: state, policy: policy) {
            return .skip(reason)
        }
        return .ask
    }

    /// The number of signals that count toward `moment`, after caps and filters.
    public static func countedSignals(
        at now: Date,
        moment: ReviewMoment,
        rule: ReviewMomentRule,
        state: ReviewState,
        policy: ReviewPolicy
    ) -> Int {
        let candidates: [ReviewSignal]
        if let scope = moment.scope {
            candidates = state.signals.filter { $0.scope == scope }
        } else {
            let lastAsk = state.asks.last?.at
            let lookback = policy.unscopedSignalLookbackDays.map { now.addingTimeInterval(-Double($0) * .day) }
            candidates = state.signals.filter { signal in
                (lastAsk.map { signal.at > $0 } ?? true) && (lookback.map { signal.at >= $0 } ?? true)
            }
        }
        let counted = candidates.filter { signal in
            signal.at <= now && (rule.countedSignals.map { $0.contains(signal.kind) } ?? true)
        }
        struct Bucket: Hashable { let kind: ReviewSignalKind; let scope: ReviewScope? }
        let perBucket = Dictionary(grouping: counted) { Bucket(kind: $0.kind, scope: $0.scope) }
        return perBucket.reduce(0) { total, entry in
            let count = entry.value.count
            return total + min(count, policy.signalCapPerScope[entry.key.kind] ?? count)
        }
    }

    // MARK: - Stages

    private static func prerequisiteFailure(
        at now: Date, moment: ReviewMoment, state: ReviewState, policy: ReviewPolicy
    ) -> ReviewSkipReason? {
        guard policy.isEnabled else { return .disabled }
        guard let rule = policy.moments[moment.name] else { return .undeclaredMoment(moment.name) }

        let daysSinceInstall = state.installedAt.map { max(0, Int(now.timeIntervalSince($0) / .day)) } ?? 0
        if state.installedAt == nil || daysSinceInstall < policy.minimumDaysSinceInstall {
            return .tooSoonAfterInstall(days: daysSinceInstall, required: policy.minimumDaysSinceInstall)
        }

        let activeDays = activeDayCount(at: now, state: state, policy: policy)
        if activeDays < policy.minimumActiveDays {
            return .tooFewActiveDays(count: activeDays, required: policy.minimumActiveDays)
        }

        if let unmet = moment.unmet.min() { return .requirementUnmet(unmet) }

        let signals = countedSignals(at: now, moment: moment, rule: rule, state: state, policy: policy)
        if signals < rule.minimumSignals {
            return .tooFewSignals(count: signals, required: rule.minimumSignals)
        }
        return nil
    }

    private static func blockerFailure(
        at now: Date, moment: ReviewMoment, state: ReviewState, policy: ReviewPolicy
    ) -> ReviewSkipReason? {
        if let ongoing = moment.ongoing.min() { return .ongoing(ongoing) }

        struct Hold { let kind: ReviewBlockerKind; let until: Date? }
        var holds: [Hold] = []
        for blocker in state.blockers {
            guard let cooldown = policy.cooldowns[blocker.kind] else { continue }
            let sameScope = blocker.scope != nil && blocker.scope == moment.scope
            if cooldown.holdsForScope, sameScope {
                holds.append(Hold(kind: blocker.kind, until: nil))
                continue
            }
            let until = blocker.at.addingTimeInterval(Double(cooldown.days) * .day)
            if now < until { holds.append(Hold(kind: blocker.kind, until: until)) }
        }
        // The hold that lasts longest says the most about when asking becomes possible again.
        let longest = holds.max { lhs, rhs in
            switch (lhs.until, rhs.until) {
            case (nil, nil): lhs.kind > rhs.kind
            case (nil, _): false
            case (_, nil): true
            case let (l?, r?): l == r ? lhs.kind > rhs.kind : l < r
            }
        }
        return longest.map { .coolingDown($0.kind, until: $0.until) }
    }

    private static func limitFailure(
        at now: Date, version: AppVersion, moment: ReviewMoment, state: ReviewState, policy: ReviewPolicy
    ) -> ReviewSkipReason? {
        let current = version.truncated(to: policy.versionGranularity)
        let inVersion = state.asks.filter { $0.version.truncated(to: policy.versionGranularity) == current }
        if inVersion.count >= policy.asksPerVersion { return .alreadyAskedThisVersion(current) }

        if let scope = moment.scope, let limit = policy.asksPerScope,
           state.asks.filter({ $0.scope == scope }).count >= limit {
            return .alreadyAskedInScope(scope)
        }

        if let last = state.asks.last {
            let until = last.at.addingTimeInterval(Double(policy.minimumDaysBetweenAsks) * .day)
            if now < until { return .tooSoonAfterLastAsk(until: until) }
        }

        let windowStart = now.addingTimeInterval(-365 * .day)
        let inWindow = state.asks.filter { $0.at > windowStart && $0.at <= now }
        if inWindow.count >= policy.maximumAsksPerYear {
            guard policy.maximumAsksPerYear > 0 else { return .yearlyLimitReached(until: .distantFuture) }
            // The window frees one slot when its oldest request leaves it.
            let freeing = inWindow[inWindow.count - policy.maximumAsksPerYear]
            return .yearlyLimitReached(until: freeing.at.addingTimeInterval(365 * .day))
        }
        return nil
    }

    private static func activeDayCount(at now: Date, state: ReviewState, policy: ReviewPolicy) -> Int {
        guard let today = ReviewDay(now, in: policy.timeZone) else { return state.activeDays.count }
        return state.activeDays.filter { $0 <= today }.count
    }
}
