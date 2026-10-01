import ReviewCore
import SwiftUI

/// A ``FeedbackSender`` that opens the feedback as a mail through SwiftUI's `OpenURLAction`.
///
/// The person sees the whole mail, diagnostics included, and sends it themselves, so the app never
/// knows whether it went: the result is ``FeedbackDelivery/handedToMail``.
///
/// ```swift
/// @Environment(\.openURL) private var openURL
///
/// let sender = MailFeedbackSender(mail: mail, openURL: openURL)
/// ```
@MainActor
public final class MailFeedbackSender: FeedbackSender {

    private let mail: FeedbackMail
    private let openURL: OpenURLAction

    public init(mail: FeedbackMail, openURL: OpenURLAction) {
        self.mail = mail
        self.openURL = openURL
    }

    public func send(_ feedback: Feedback) async throws(FeedbackError) -> FeedbackDelivery {
        let url = try mail.url(for: feedback)
        let accepted = await withCheckedContinuation { continuation in
            openURL(url) { continuation.resume(returning: $0) }
        }
        guard accepted else { throw .noMailClient }
        return .handedToMail
    }
}
