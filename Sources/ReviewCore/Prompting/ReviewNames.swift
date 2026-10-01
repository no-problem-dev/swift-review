/// A kind of good outcome the app counts toward asking for a rating, such as "booked a hotel" or
/// "saved a trip journal".
///
/// The package has no built-in kinds. Each app declares its own, usually as static constants:
///
/// ```swift
/// extension ReviewSignalKind {
///     static let movementDecided: Self = "movement_decided"
///     static let journalSaved: Self = "journal_saved"
/// }
/// ```
///
/// The raw value is stored on the device and shows up in metrics, so keep it stable and in
/// snake_case. Renaming one drops what was already counted under the old name.
public struct ReviewSignalKind: RawRepresentable, Hashable, Comparable, Sendable, Codable,
    ExpressibleByStringLiteral, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A kind of event or condition that holds a request back, such as "dismissed the paywall",
/// "saw an error" or "offline".
///
/// The same kind can be used both as a recorded event (``ReviewPrompter/block(_:in:)``, held back
/// for the ``ReviewCooldown`` the policy gives it) and as a condition in effect right now
/// (``ReviewMoment/ongoing``).
public struct ReviewBlockerKind: RawRepresentable, Hashable, Comparable, Sendable, Codable,
    ExpressibleByStringLiteral, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The name of a place in the app where asking is allowed at all, such as "after saving the trip
/// journal".
///
/// Only moments declared in ``ReviewPolicy/moments`` can ever lead to a request; any other name is
/// refused with ``ReviewSkipReason/undeclaredMoment(_:)``. That keeps "where do we ask" a list you
/// can read in one place, instead of a property of whichever screen happens to call.
public struct ReviewMomentName: RawRepresentable, Hashable, Comparable, Sendable, Codable,
    ExpressibleByStringLiteral, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The unit signals are grouped by, such as one trip, one project or one document.
///
/// A moment in a scope counts only that scope's signals, and blockers recorded in a scope can hold
/// back that scope alone (see ``ReviewCooldown/holdsForScope``). Use an identifier the app already
/// has; the package treats it as opaque text.
public struct ReviewScope: RawRepresentable, Hashable, Comparable, Sendable, Codable,
    ExpressibleByStringLiteral, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// An app-specific precondition the package cannot see, such as "has created a trip of their own".
///
/// The app checks it and, when it does not hold, names it in ``ReviewMoment/unmet``. It is reported
/// as a prerequisite, so it never counts as "eligible but blocked" in metrics.
public struct ReviewRequirement: RawRepresentable, Hashable, Comparable, Sendable, Codable,
    ExpressibleByStringLiteral, CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
