import Foundation

/// A calendar date with no time zone, used to count the days on which the app was opened.
///
/// "Opened on three days" depends on where the day boundary falls, so the date is always read in
/// the policy's ``ReviewPolicy/timeZone``, never in the device's current one. Text, `Codable`
/// and sorting use `YYYY-MM-DD`.
public struct ReviewDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {

    public let year: Int
    public let month: Int
    public let day: Int

    /// Creates a date from its parts, or `nil` when they do not name a real Gregorian date.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...ReviewDay.daysIn(month: month, year: year)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The date an instant falls on in a time zone, or `nil` for an instant that is not a date
    /// (NaN, infinite, or outside years 1 through 9999).
    public init?(_ instant: Date, in timeZone: TimeZone) {
        guard instant.timeIntervalSince1970.isFinite else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: instant)
        guard parts.era == 1, let year = parts.year, let month = parts.month, let day = parts.day else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// Parses `YYYY-MM-DD`.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// Days from this date to `other`; negative when `other` is earlier.
    public func days(to other: ReviewDay) -> Int {
        other.ordinal - ordinal
    }

    public var description: String {
        let y = String(year), m = String(month), d = String(day)
        return String(repeating: "0", count: 4 - y.count) + y + "-"
            + (m.count == 1 ? "0" : "") + m + "-"
            + (d.count == 1 ? "0" : "") + d
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.ordinal < rhs.ordinal }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = ReviewDay(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a date: \(text)")
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`), so day arithmetic needs no
    /// `Calendar`.
    private var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}
