import Foundation
import Observation
import ReviewCore
import SwiftUI

/// A ``FeedbackSender`` that shows the system mail composer, so feedback can carry one attachment
/// such as a screenshot.
///
/// Like ``ReviewRequestBridge``, the sender only carries the feedback to a view: the view that
/// applied `feedbackMailComposer(_:)` (iOS) presents the composer over whatever is on screen,
/// sheets included, and finishes the send. The person sees the whole mail and sends it themselves.
///
/// | What the view finds | Result |
/// |---|---|
/// | The device can send mail | The composer, with the attachments. Sent or saved → ``FeedbackDelivery/handedToMail``; closed → ``FeedbackError/cancelled`` |
/// | No mail account is set up | A `mailto:` link through `OpenURLAction`, **without the attachments**. Accepted → ``FeedbackDelivery/handedToMail``; refused → ``FeedbackError/noMailClient`` |
/// | No view is attached | ``FeedbackError/noMailClient`` |
///
/// ```swift
/// @State private var mail = MailComposerFeedbackSender(mail: feedbackMail)
///
/// var body: some View {
///     RootView().feedbackMailComposer(mail)
/// }
/// ```
@MainActor
@Observable
public final class MailComposerFeedbackSender: FeedbackSender {

    struct Pending {
        let id: UUID
        let feedback: Feedback
        let continuation: CheckedContinuation<Result<FeedbackDelivery, FeedbackError>, Never>
    }

    /// The recipient and the words around the person's text.
    public let mail: FeedbackMail

    private(set) var pendingID: UUID?
    @ObservationIgnored private var pending: Pending?
    @ObservationIgnored private var hosts = 0

    public init(mail: FeedbackMail) {
        self.mail = mail
    }

    /// Whether a view is attached to show the composer.
    public var hasHost: Bool { hosts > 0 }

    public func send(_ feedback: Feedback) async throws(FeedbackError) -> FeedbackDelivery {
        guard hasHost else { throw .noMailClient }
        guard pending == nil else { throw .transportFailed("Another mail is already open") }
        let result = await withCheckedContinuation { continuation in
            let id = UUID()
            pending = Pending(id: id, feedback: feedback, continuation: continuation)
            pendingID = id
        }
        return try result.get()
    }

    var pendingFeedback: Feedback? { pending?.feedback }

    func attachHost() {
        hosts += 1
    }

    func detachHost() {
        hosts = max(0, hosts - 1)
        if hosts == 0, let id = pendingID { resolve(id, with: .failure(.cancelled)) }
    }

    /// Finishes the send if it is still the pending one; later calls for the same id do nothing.
    func resolve(_ id: UUID, with result: Result<FeedbackDelivery, FeedbackError>) {
        guard let current = pending, current.id == id else { return }
        pending = nil
        pendingID = nil
        current.continuation.resume(returning: result)
    }
}

#if os(iOS)
import MessageUI
import UIKit

struct FeedbackMailComposerHost: ViewModifier {

    let sender: MailComposerFeedbackSender

    @Environment(\.openURL) private var openURL
    @State private var delegate: MailComposeDelegate?

    func body(content: Content) -> some View {
        content
            .onAppear { sender.attachHost() }
            .onDisappear { sender.detachHost() }
            .task(id: sender.pendingID) {
                guard let id = sender.pendingID, let feedback = sender.pendingFeedback else { return }
                if MFMailComposeViewController.canSendMail(), present(id: id, feedback: feedback) { return }
                openMailLink(id: id, feedback: feedback)
            }
    }

    /// Presents the composer over whatever is on top, sheets included. A SwiftUI `.sheet` on the
    /// root cannot appear while the app already shows a sheet, which is where feedback screens live.
    private func present(id: UUID, feedback: Feedback) -> Bool {
        guard let top = UIApplication.shared.topViewController else { return false }
        let delegate = MailComposeDelegate { result in
            sender.resolve(id, with: result)
            self.delegate = nil
        }
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = delegate
        controller.setToRecipients([sender.mail.recipient])
        controller.setSubject(sender.mail.labels.subject(for: feedback.kind))
        controller.setMessageBody(sender.mail.body(for: feedback), isHTML: false)
        for attachment in feedback.attachments {
            controller.addAttachmentData(attachment.data, mimeType: attachment.contentType, fileName: attachment.filename)
        }
        self.delegate = delegate
        top.present(controller, animated: true)
        return true
    }

    private func openMailLink(id: UUID, feedback: Feedback) {
        let url: URL
        do {
            url = try sender.mail.url(for: feedback, omittingAttachments: true)
        } catch {
            return sender.resolve(id, with: .failure(error))
        }
        openURL(url) { accepted in
            sender.resolve(id, with: accepted ? .success(.handedToMail) : .failure(.noMailClient))
        }
    }
}

@MainActor
final class MailComposeDelegate: NSObject, MFMailComposeViewControllerDelegate {

    private let finish: (Result<FeedbackDelivery, FeedbackError>) -> Void

    init(finish: @escaping (Result<FeedbackDelivery, FeedbackError>) -> Void) {
        self.finish = finish
    }

    nonisolated func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: (any Error)?
    ) {
        let outcome: Result<FeedbackDelivery, FeedbackError> = switch result {
        case .sent, .saved: .success(.handedToMail)
        case .cancelled: .failure(.cancelled)
        case .failed: .failure(.transportFailed(error.map { String(describing: $0) } ?? "The mail could not be sent"))
        @unknown default: .failure(.transportFailed("The mail composer finished in an unknown way"))
        }
        MainActor.assumeIsolated {
            controller.dismiss(animated: true)
            finish(outcome)
        }
    }
}

extension UIApplication {

    fileprivate var topViewController: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

extension View {

    /// Shows the system mail composer for feedback handed to `sender`, over any sheet on screen,
    /// and falls back to a `mailto:` link (without attachments) when the device has no mail
    /// account. Apply it once, near the root.
    public func feedbackMailComposer(_ sender: MailComposerFeedbackSender) -> some View {
        modifier(FeedbackMailComposerHost(sender: sender))
    }
}
#endif
