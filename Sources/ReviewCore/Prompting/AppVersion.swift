import Foundation

/// The marketing version of the app (`CFBundleShortVersionString`), such as `1.4.2`.
///
/// "Once per version" depends on which part of the number counts as a new version. A fix-only
/// release (`1.4.2` → `1.4.3`) usually should not earn another request; see ``Granularity``.
public struct AppVersion: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {

    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses one to three dot-separated non-negative integers, such as `"2"`, `"2.1"` or `"2.1.3"`.
    ///
    /// Returns `nil` for anything else (`"2.1b"`, `""`, `"1.2.3.4"`), because a version that cannot
    /// be compared would make "once per version" mean nothing.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                  let number = Int(part) else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    /// Reads `CFBundleShortVersionString` from a bundle, or `nil` when it is missing or unreadable.
    public init?(bundle: Bundle) {
        guard let text = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        self.init(text)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// Which part of the number makes a version new for "once per version".
    public enum Granularity: String, Sendable, Codable, CaseIterable {
        /// `1.x` → `2.0` only.
        case major
        /// `1.4` → `1.5`. A fix-only release keeps the same version. The usual choice.
        case minor
        /// Every release, including `1.4.2` → `1.4.3`.
        case patch
    }

    /// The version with the parts finer than `granularity` set to zero, so two versions compare
    /// equal exactly when they are the same version at that granularity.
    public func truncated(to granularity: Granularity) -> AppVersion {
        switch granularity {
        case .major: AppVersion(major: major)
        case .minor: AppVersion(major: major, minor: minor)
        case .patch: self
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let version = AppVersion(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a version: \(text)")
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
