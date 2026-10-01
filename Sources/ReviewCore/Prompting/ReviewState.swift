import Foundation

/// Everything the decision reads, kept on the device and never synchronised.
///
/// The system's limit is counted per device, and a request made on another device does not use up
/// this one's, so a synchronised record would make the app ask less than it may without making the
/// system ask less.
///
/// ## Versioned, and keeps what it does not know
///
/// The stored form carries ``schemaVersion``. A store refuses to read a newer schema
/// (``ReviewStoreError/newerSchema(found:supported:)``) and the prompter then neither asks nor
/// writes, so a downgraded build cannot wipe what a newer build recorded. Top-level fields this
/// build does not know are kept as they were and written back unchanged.
public struct ReviewState: Sendable, Equatable {

    /// The stored form this build reads and writes.
    public static let schemaVersion = 1

    /// The first recorded launch, or `nil` before any.
    public var installedAt: Date?
    /// Distinct days of use, ascending.
    public private(set) var activeDays: [ReviewDay]
    /// Good outcomes, oldest first.
    public private(set) var signals: [ReviewSignal]
    /// The latest blocker per kind and scope.
    public private(set) var blockers: [ReviewBlocker]
    /// Calls to the system's review request, oldest first.
    public private(set) var asks: [ReviewAsk]

    /// Fields from a newer build, as JSON, written back as they were.
    var unknownFields: [String: Data]

    public init(
        installedAt: Date? = nil,
        activeDays: [ReviewDay] = [],
        signals: [ReviewSignal] = [],
        blockers: [ReviewBlocker] = [],
        asks: [ReviewAsk] = []
    ) {
        self.installedAt = installedAt
        self.activeDays = Array(Set(activeDays)).sorted()
        self.signals = signals.sorted { $0.at < $1.at }
        self.blockers = []
        self.asks = asks.sorted { $0.at < $1.at }
        self.unknownFields = [:]
        for blocker in blockers { record(blocker) }
    }

    // MARK: - Recording

    /// Stamps the install time if none is stored, and adds the day `now` falls on in `timeZone`.
    ///
    /// Days older than `retainingDays` before today are dropped.
    public mutating func markActive(at now: Date, in timeZone: TimeZone, retainingDays: Int) {
        if installedAt == nil { installedAt = now }
        guard let today = ReviewDay(now, in: timeZone) else { return }
        if !activeDays.contains(today) {
            activeDays.append(today)
            activeDays.sort()
        }
        activeDays.removeAll { $0.days(to: today) >= retainingDays }
    }

    public mutating func record(_ signal: ReviewSignal) {
        let index = signals.lastIndex { $0.at <= signal.at }.map { $0 + 1 } ?? 0
        signals.insert(signal, at: index)
    }

    /// Removes the most recent signal of this kind in this scope, for an action the person undid.
    ///
    /// - Returns: `true` when one was removed.
    @discardableResult
    public mutating func retract(_ kind: ReviewSignalKind, in scope: ReviewScope?) -> Bool {
        guard let index = signals.lastIndex(where: { $0.kind == kind && $0.scope == scope }) else { return false }
        signals.remove(at: index)
        return true
    }

    /// Keeps the blocker if it is the latest of its kind and scope.
    public mutating func record(_ blocker: ReviewBlocker) {
        if let index = blockers.firstIndex(where: { $0.kind == blocker.kind && $0.scope == blocker.scope }) {
            if blockers[index].at < blocker.at { blockers[index] = blocker }
        } else {
            blockers.append(blocker)
        }
    }

    public mutating func record(_ ask: ReviewAsk) {
        let index = asks.lastIndex { $0.at <= ask.at }.map { $0 + 1 } ?? 0
        asks.insert(ask, at: index)
    }

    /// Drops the scope's signals and blockers, for a trip or document that was deleted.
    ///
    /// Requests made in the scope stay: they still count toward the version and yearly limits.
    public mutating func forget(_ scope: ReviewScope) {
        signals.removeAll { $0.scope == scope }
        blockers.removeAll { $0.scope == scope }
    }

    /// Drops what can no longer change any decision under `policy`.
    ///
    /// - Signals older than ``ReviewPolicy/signalRetentionDays``
    /// - Blockers whose cooldown has run out (or that have none), except those that hold their scope
    /// - Requests older than 365 days, except the latest one of each version
    public mutating func prune(at now: Date, policy: ReviewPolicy) {
        let signalHorizon = now.addingTimeInterval(-Double(policy.signalRetentionDays) * .day)
        signals.removeAll { $0.at < signalHorizon }

        blockers.removeAll { blocker in
            guard let cooldown = policy.cooldowns[blocker.kind] else { return true }
            if cooldown.holdsForScope, blocker.scope != nil { return false }
            return blocker.at.addingTimeInterval(Double(cooldown.days) * .day) <= now
        }

        let yearAgo = now.addingTimeInterval(-365 * .day)
        var latestPerVersion: [AppVersion: Date] = [:]
        for ask in asks {
            let key = ask.version.truncated(to: policy.versionGranularity)
            latestPerVersion[key] = max(latestPerVersion[key] ?? ask.at, ask.at)
        }
        asks.removeAll { ask in
            ask.at < yearAgo && latestPerVersion[ask.version.truncated(to: policy.versionGranularity)] != ask.at
        }
    }

    // MARK: - Stored form

    /// Encodes the state with ``schemaVersion`` and any fields kept from a newer build.
    public func encoded() throws(ReviewStoreError) -> Data {
        do {
            let known = try JSONEncoder.review.encode(StoredForm(self))
            guard var object = try JSONSerialization.jsonObject(with: known) as? [String: Any] else {
                throw ReviewStoreError.unencodable
            }
            for (key, fragment) in unknownFields where object[key] == nil {
                object[key] = try JSONSerialization.jsonObject(with: fragment, options: .fragmentsAllowed)
            }
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch let error as ReviewStoreError {
            throw error
        } catch {
            throw .unencodable
        }
    }

    /// Decodes a stored state.
    ///
    /// - Throws: ``ReviewStoreError/newerSchema(found:supported:)`` for a schema this build does not
    ///   know, and ``ReviewStoreError/corrupt`` for anything that is not a stored state.
    public static func decode(_ data: Data) throws(ReviewStoreError) -> ReviewState {
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ReviewStoreError.corrupt
            }
            object = parsed
        } catch {
            throw .corrupt
        }
        guard let schema = object[StoredForm.CodingKeys.schema.rawValue] as? Int else { throw .corrupt }
        guard schema <= schemaVersion else { throw .newerSchema(found: schema, supported: schemaVersion) }

        var state: ReviewState
        do {
            state = try JSONDecoder.review.decode(StoredForm.self, from: data).state
        } catch {
            throw .corrupt
        }
        let knownKeys = Set(StoredForm.CodingKeys.allCases.map(\.rawValue))
        for (key, value) in object where !knownKeys.contains(key) {
            guard let fragment = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else {
                throw .corrupt
            }
            state.unknownFields[key] = fragment
        }
        return state
    }

    private struct StoredForm: Codable {
        enum CodingKeys: String, CodingKey, CaseIterable {
            case schema, installedAt, activeDays, signals, blockers, asks
        }

        var schema: Int
        var installedAt: Date?
        var activeDays: [ReviewDay]
        var signals: [ReviewSignal]
        var blockers: [ReviewBlocker]
        var asks: [ReviewAsk]

        init(_ state: ReviewState) {
            schema = ReviewState.schemaVersion
            installedAt = state.installedAt
            activeDays = state.activeDays
            signals = state.signals
            blockers = state.blockers
            asks = state.asks
        }

        var state: ReviewState {
            ReviewState(installedAt: installedAt, activeDays: activeDays, signals: signals,
                        blockers: blockers, asks: asks)
        }
    }
}

extension TimeInterval {
    static let day: TimeInterval = 86_400
}

extension JSONEncoder {
    static var review: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var review: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
