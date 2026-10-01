import Foundation

/// Turns feedback into a `mailto:` link, so the person sees and sends the whole mail themselves.
///
/// This is the channel that needs no server. Attachments cannot travel in a link, so feedback that
/// carries any is refused with ``FeedbackError/attachmentsUnsupported`` instead of being sent without
/// them.
///
/// Every word that appears in the mail comes from the app, so the mail reads in the app's language.
public struct FeedbackMail: Hashable, Sendable {

    /// The words around the person's text.
    public struct Labels: Hashable, Sendable {
        /// The subject for each kind; kinds without one use ``fallbackSubject``.
        public var subjects: [FeedbackKind: String]
        public var fallbackSubject: String
        public var replyTo: String
        public var diagnostics: String

        public init(subjects: [FeedbackKind: String], fallbackSubject: String, replyTo: String, diagnostics: String) {
            self.subjects = subjects
            self.fallbackSubject = fallbackSubject
            self.replyTo = replyTo
            self.diagnostics = diagnostics
        }

        public func subject(for kind: FeedbackKind) -> String {
            subjects[kind] ?? fallbackSubject
        }
    }

    public var recipient: String
    public var labels: Labels

    public init(recipient: String, labels: Labels) {
        self.recipient = recipient
        self.labels = labels
    }

    /// The mail body: the text, then the reply address and diagnostics when present.
    public func body(for feedback: Feedback) -> String {
        var sections = [feedback.text]
        if let address = feedback.replyAddress {
            sections.append("\(labels.replyTo): \(address.rawValue)")
        }
        if let diagnostics = feedback.diagnostics, !diagnostics.entries.isEmpty {
            sections.append(([labels.diagnostics] + diagnostics.lines).joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    /// The `mailto:` link for `feedback`.
    ///
    /// Feedback with attachments is refused with ``FeedbackError/attachmentsUnsupported`` unless
    /// `omittingAttachments` is `true`, which builds the link from the text and diagnostics alone.
    /// A caller that omits them is the fallback when no mail composer is available, and the person
    /// can still attach the file by hand in the mail app.
    public func url(for feedback: Feedback, omittingAttachments: Bool = false) throws(FeedbackError) -> URL {
        guard omittingAttachments || feedback.attachments.isEmpty else { throw .attachmentsUnsupported }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: labels.subject(for: feedback.kind)),
            URLQueryItem(name: "body", value: body(for: feedback))
        ]
        // URLComponents leaves "+" alone in queries, and mail apps read it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw .transportFailed("Could not build a mail link") }
        return url
    }
}

/// The JSON body ``HTTPFeedbackSender`` posts.
///
/// ```json
/// {"kind":"bug","text":"…","replyAddress":"a@example.com",
///  "diagnostics":[{"key":"app_version","value":"1.4.0"}],
///  "attachments":[{"filename":"screen.png","contentType":"image/png","data":"<base64>"}]}
/// ```
///
/// `replyAddress` and `diagnostics` are left out when absent, so "the person did not agree" and
/// "there was nothing to send" look the same to the server.
public struct FeedbackPayload: Encodable, Sendable {

    struct Attachment: Encodable, Sendable {
        let filename: String
        let contentType: String
        let data: Data
    }

    let kind: String
    let text: String
    let replyAddress: String?
    let diagnostics: [FeedbackDiagnostics.Entry]?
    let attachments: [Attachment]

    public init(_ feedback: Feedback) {
        kind = feedback.kind.rawValue
        text = feedback.text
        replyAddress = feedback.replyAddress?.rawValue
        diagnostics = feedback.diagnostics?.entries
        attachments = feedback.attachments.map {
            Attachment(filename: $0.filename, contentType: $0.contentType, data: $0.data)
        }
    }

    /// The payload as JSON with sorted keys; attachment bytes are base64.
    public func encoded() throws(FeedbackError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dataEncodingStrategy = .base64
        do {
            return try encoder.encode(self)
        } catch {
            throw .transportFailed("Could not encode the feedback")
        }
    }
}

/// Posts feedback as JSON to an endpoint, through a transport the app supplies.
///
/// The package does not talk to the network itself: the app passes the function that performs a
/// request, usually its existing HTTP client (`swift-http-transport`, a generated API client, or
/// `URLSession` in a small app). That keeps authentication, App Check, retries and logging where
/// the app already has them.
///
/// ```swift
/// let sender = HTTPFeedbackSender(endpoint: url) { request in
///     try await transport.send(request)   // returns (Data, HTTPURLResponse)
/// }
/// ```
public struct HTTPFeedbackSender: FeedbackSender {

    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let endpoint: URL
    private let headers: [String: String]
    private let transport: Transport

    public init(endpoint: URL, headers: [String: String] = [:], transport: @escaping Transport) {
        self.endpoint = endpoint
        self.headers = headers
        self.transport = transport
    }

    /// The request that ``send(_:)`` hands to the transport.
    public func request(for feedback: Feedback) throws(FeedbackError) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try FeedbackPayload(feedback).encoded()
        return request
    }

    public func send(_ feedback: Feedback) async throws(FeedbackError) -> FeedbackDelivery {
        let request = try request(for: feedback)
        let response: HTTPURLResponse
        do {
            (_, response) = try await transport(request)
        } catch {
            throw .transportFailed(String(describing: error))
        }
        guard (200..<300).contains(response.statusCode) else { throw .rejected(status: response.statusCode) }
        return .delivered(receipt: response.value(forHTTPHeaderField: "Location"))
    }
}
