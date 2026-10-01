import Foundation

/// Why stored state could not be read or written.
public enum ReviewStoreError: Error, Sendable, Hashable, LocalizedError {
    /// The stored state was written by a newer build. It is left untouched.
    case newerSchema(found: Int, supported: Int)
    /// What is stored is not a review state.
    case corrupt
    /// The state could not be turned into its stored form.
    case unencodable

    public var errorDescription: String? {
        switch self {
        case let .newerSchema(found, supported):
            "The review state was written by a newer build (schema \(found); this build reads up to \(supported))."
        case .corrupt:
            "The stored review state is not readable."
        case .unencodable:
            "The review state could not be encoded."
        }
    }
}

/// Where ``ReviewState`` is kept between launches.
///
/// Keep it on the device and out of any sync or backup the app controls: the system's limit is per
/// device (see ``ReviewState``).
public protocol ReviewStateStore: Sendable {

    /// The stored state, or `nil` when nothing has been stored yet.
    func load() throws(ReviewStoreError) -> ReviewState?

    /// Replaces the stored state.
    func save(_ state: ReviewState) throws(ReviewStoreError)

    /// Removes the stored state, as on account deletion.
    func clear()
}

/// A ``ReviewStateStore`` that keeps the state as JSON under one `UserDefaults` key.
///
/// It holds the suite's **name**, not a `UserDefaults` instance, and opens the suite on each call:
/// `UserDefaults` is not `Sendable`, and the name is all that is needed to reach the same storage.
/// Tests pass a suite of their own, since tests running in parallel against `standard` would write
/// over each other.
///
/// ```swift
/// let store = UserDefaultsReviewStateStore()                                     // standard
/// let shared = UserDefaultsReviewStateStore(suiteName: "group.com.example.app")  // app group
/// ```
public struct UserDefaultsReviewStateStore: ReviewStateStore {

    private let suiteName: String?
    private let key: String

    /// The store in `UserDefaults.standard`.
    ///
    /// - Parameter key: The key to store under. Change it only to avoid a collision.
    public init(key: String = "review.state") {
        self.suiteName = nil
        self.key = key
    }

    /// The store in a named suite, or `nil` when `UserDefaults` refuses the name (such as the app's
    /// own bundle identifier, or `NSGlobalDomain`).
    public init?(suiteName: String, key: String = "review.state") {
        guard UserDefaults(suiteName: suiteName) != nil else { return nil }
        self.suiteName = suiteName
        self.key = key
    }

    private var defaults: UserDefaults {
        // The name was accepted in init, and UserDefaults refuses a name only by what it is.
        suiteName.map { UserDefaults(suiteName: $0)! } ?? .standard
    }

    public func load() throws(ReviewStoreError) -> ReviewState? {
        guard let stored = defaults.object(forKey: key) else { return nil }
        guard let data = stored as? Data else { throw .corrupt }
        return try ReviewState.decode(data)
    }

    public func save(_ state: ReviewState) throws(ReviewStoreError) {
        defaults.set(try state.encoded(), forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// A ``ReviewStateStore`` that keeps the state in memory, for previews and development builds.
///
/// It goes through the same stored form as a real store, so a state that would not survive
/// encoding fails here too.
public final class InMemoryReviewStateStore: ReviewStateStore {

    private let storage: Locked<Data?>

    /// Starts empty.
    public init() {
        storage = Locked(nil)
    }

    /// Starts from a state, encoded as a real store would.
    public init(_ state: ReviewState) throws(ReviewStoreError) {
        storage = Locked(try state.encoded())
    }

    /// Starts from stored bytes as they are, such as a state written by a newer schema.
    public init(storedData: Data) {
        storage = Locked(storedData)
    }

    /// The bytes as they would be stored.
    public var storedData: Data? { storage.value }

    public func load() throws(ReviewStoreError) -> ReviewState? {
        guard let data = storage.value else { return nil }
        return try ReviewState.decode(data)
    }

    public func save(_ state: ReviewState) throws(ReviewStoreError) {
        let data = try state.encoded()
        storage.withValue { $0 = data }
    }

    public func clear() {
        storage.withValue { $0 = nil }
    }
}
