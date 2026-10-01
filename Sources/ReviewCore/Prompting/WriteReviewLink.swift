import Foundation

/// An app's numeric App Store identifier, the digits after `id` in its store URL.
public struct AppStoreID: Hashable, Sendable, Codable, CustomStringConvertible {

    public let rawValue: String

    /// Returns `nil` unless the text is one or more ASCII digits, so a placeholder such as
    /// `"APP_STORE_ID"` or an empty build setting never becomes a link.
    public init?(_ text: String) {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        rawValue = text
    }

    public var description: String { rawValue }
}

/// The link that opens the App Store's write-a-review page for an app.
///
/// Put it where the person chooses to press it, such as a settings row. It is not a request: it
/// does not count toward any limit, and Apple's sample code uses the same form.
///
/// ```swift
/// if let id = AppStoreID(config.appStoreID) {
///     Link("Rate on the App Store", destination: WriteReviewLink.url(for: id))
/// }
/// ```
public enum WriteReviewLink {

    /// `https://apps.apple.com/app/id<ID>?action=write-review`
    public static func url(for id: AppStoreID) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "apps.apple.com"
        components.path = "/app/id\(id.rawValue)"
        components.queryItems = [URLQueryItem(name: "action", value: "write-review")]
        // The parts above are fixed ASCII and digits, so the URL always exists.
        return components.url!
    }
}
