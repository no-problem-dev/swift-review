import Foundation

/// What a piece of feedback is about.
///
/// Three kinds are provided; an app may declare more. The raw value is sent, so keep it stable.
public struct FeedbackKind: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible {

    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    /// Something does not work.
    public static let bug: FeedbackKind = "bug"
    /// Something the person would like the app to do.
    public static let request: FeedbackKind = "request"
    /// Anything else.
    public static let other: FeedbackKind = "other"
}

/// An address to reply to, checked only for shape.
///
/// The check is deliberately loose (one `@`, something on each side, a dot in the domain, no
/// spaces). Its job is to catch a typo like a missing `@`, not to decide which addresses exist.
public struct FeedbackReplyAddress: Hashable, Sendable, Codable, CustomStringConvertible {

    public let rawValue: String

    /// Trims surrounding whitespace, then returns `nil` when the text is not shaped like an address.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              !trimmed.contains(where: \.isWhitespace) else { return nil }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return nil }
        rawValue = trimmed
    }

    public var description: String { rawValue }
}

/// A file the person chose to send, such as one screenshot.
public struct FeedbackAttachment: Hashable, Sendable {

    public var filename: String
    /// A MIME type, such as `image/png`.
    public var contentType: String
    public var data: Data

    public init(filename: String, contentType: String, data: Data) {
        self.filename = filename
        self.contentType = contentType
        self.data = data
    }
}

/// Facts about the device and the app that help with a bug report, sent only when the person turns
/// them on.
///
/// **The app chooses the entries.** Keep them to versions, settings and error codes: nothing the
/// person wrote and nothing about their content. The same ``lines`` are shown before sending and
/// sent, so "what you see is what is sent" holds by construction.
public struct FeedbackDiagnostics: Hashable, Sendable {

    public struct Entry: Hashable, Sendable, Codable {
        public var key: String
        public var value: String

        public init(_ key: String, _ value: String) {
            self.key = key
            self.value = value
        }
    }

    /// In the order they are shown and sent.
    public var entries: [Entry]

    public init(_ entries: [Entry]) {
        self.entries = entries
    }

    /// One `key: value` line per entry.
    public var lines: [String] {
        entries.map { "\($0.key): \($0.value)" }
    }
}

/// Limits a draft has to satisfy before it can be sent.
public struct FeedbackLimits: Hashable, Sendable {

    public var maximumTextLength: Int
    public var maximumAttachments: Int
    public var maximumAttachmentBytes: Int

    public init(maximumTextLength: Int = 1_000, maximumAttachments: Int = 1, maximumAttachmentBytes: Int = 10_000_000) {
        self.maximumTextLength = maximumTextLength
        self.maximumAttachments = maximumAttachments
        self.maximumAttachmentBytes = maximumAttachmentBytes
    }
}

/// Feedback being written, as the screen holds it.
///
/// Diagnostics are **off by default**. They travel only when ``includesDiagnostics`` is turned on,
/// and ``diagnosticsPreview`` is exactly what would be sent.
public struct FeedbackDraft: Hashable, Sendable {

    public var kind: FeedbackKind
    public var text: String
    /// What the person typed as a reply address; empty for none.
    public var replyAddress: String
    public var attachments: [FeedbackAttachment]
    /// What the app would attach if the person agrees.
    public var availableDiagnostics: FeedbackDiagnostics?
    public var includesDiagnostics: Bool

    public init(
        kind: FeedbackKind = .request,
        text: String = "",
        replyAddress: String = "",
        attachments: [FeedbackAttachment] = [],
        availableDiagnostics: FeedbackDiagnostics? = nil,
        includesDiagnostics: Bool = false
    ) {
        self.kind = kind
        self.text = text
        self.replyAddress = replyAddress
        self.attachments = attachments
        self.availableDiagnostics = availableDiagnostics
        self.includesDiagnostics = includesDiagnostics
    }

    /// What would be sent as diagnostics, line by line; empty when they are off.
    public var diagnosticsPreview: [String] {
        includesDiagnostics ? (availableDiagnostics?.lines ?? []) : []
    }

    /// The draft as feedback ready to send, or the first problem with it.
    public func validated(limits: FeedbackLimits = FeedbackLimits()) throws(FeedbackError) -> Feedback {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw .emptyText }
        guard body.count <= limits.maximumTextLength else { throw .textTooLong(limit: limits.maximumTextLength) }

        let address: FeedbackReplyAddress?
        if replyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            address = nil
        } else {
            guard let parsed = FeedbackReplyAddress(replyAddress) else { throw .invalidReplyAddress }
            address = parsed
        }

        guard attachments.count <= limits.maximumAttachments else {
            throw .tooManyAttachments(limit: limits.maximumAttachments)
        }
        if attachments.contains(where: { $0.data.count > limits.maximumAttachmentBytes }) {
            throw .attachmentTooLarge(limit: limits.maximumAttachmentBytes)
        }

        return Feedback(
            kind: kind,
            text: body,
            replyAddress: address,
            attachments: attachments,
            diagnostics: includesDiagnostics ? availableDiagnostics : nil
        )
    }
}

/// Feedback that passed validation. Diagnostics are present only when the person agreed.
public struct Feedback: Hashable, Sendable {

    public let kind: FeedbackKind
    public let text: String
    public let replyAddress: FeedbackReplyAddress?
    public let attachments: [FeedbackAttachment]
    public let diagnostics: FeedbackDiagnostics?
}

/// Why feedback could not be validated or sent.
public enum FeedbackError: Error, Sendable, Equatable, LocalizedError {
    case emptyText
    case textTooLong(limit: Int)
    case invalidReplyAddress
    case tooManyAttachments(limit: Int)
    case attachmentTooLarge(limit: Int)
    /// The channel cannot carry attachments (a `mailto:` link, for one).
    case attachmentsUnsupported
    /// No app accepted the mail link, and no mail composer could be shown.
    case noMailClient
    /// The person closed the mail composer without sending.
    case cancelled
    /// The server answered with a status outside 200–299.
    case rejected(status: Int)
    /// The request did not complete.
    case transportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyText: "The message is empty."
        case let .textTooLong(limit): "The message is longer than \(limit) characters."
        case .invalidReplyAddress: "The reply address is not an email address."
        case let .tooManyAttachments(limit): "More than \(limit) attachments."
        case let .attachmentTooLarge(limit): "An attachment is larger than \(limit) bytes."
        case .attachmentsUnsupported: "This channel cannot carry attachments."
        case .noMailClient: "No app could open the mail."
        case .cancelled: "The mail was closed without sending."
        case let .rejected(status): "The server refused the feedback (status \(status))."
        case let .transportFailed(message): "The feedback could not be sent: \(message)"
        }
    }
}

/// How far feedback got.
public enum FeedbackDelivery: Hashable, Sendable {
    /// A mail was opened for the person to send. Whether they sent it is unknown.
    case handedToMail
    /// Kept on the device, to go out when the network returns.
    case queued
    /// The server accepted it, optionally with its own identifier.
    case delivered(receipt: String?)

    /// `mail` or `server`, for metrics.
    public var channel: String {
        switch self {
        case .handedToMail: "mail"
        case .queued, .delivered: "server"
        }
    }
}

/// The port through which feedback leaves the app.
public protocol FeedbackSender: Sendable {
    func send(_ feedback: Feedback) async throws(FeedbackError) -> FeedbackDelivery
}
