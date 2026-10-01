import Foundation
import SwiftUI
import Testing
import ReviewCore
@testable import ReviewSwiftUI

@MainActor
@Suite("画面の側: 頼む口の受け渡しとメールの送り口")
struct ReviewSwiftUITests {

    private let moment = ReviewMoment("journal_saved", in: "trip-a")

    @Test("受ける画面が無ければ、頼まずに取りやめる")
    func noHost() async {
        let bridge = ReviewRequestBridge()
        #expect(await bridge.requestReview(for: moment) == .abandoned(.noHost))
    }

    @Test("受ける画面があれば待っている依頼になり、画面が呼んだら requested を返す")
    func hostResolvesRequested() async throws {
        let bridge = ReviewRequestBridge()
        bridge.attachHost()
        let task = Task { await bridge.requestReview(for: moment) }
        try await waitUntil { bridge.pendingID != nil }
        #expect(bridge.pendingMoment == moment)

        bridge.resolve(try #require(bridge.pendingID), with: .requested)
        #expect(await task.value == .requested)
        #expect(bridge.pendingID == nil)
    }

    @Test("待っている依頼がある間の次の依頼は取りやめる")
    func secondRequestWhilePending() async throws {
        let bridge = ReviewRequestBridge()
        bridge.attachHost()
        let first = Task { await bridge.requestReview(for: moment) }
        try await waitUntil { bridge.pendingID != nil }

        #expect(await bridge.requestReview(for: moment) == .abandoned(.alreadyPending))
        bridge.resolve(try #require(bridge.pendingID), with: .requested)
        #expect(await first.value == .requested)
    }

    @Test("受ける画面が消えたら、待っている依頼は取りやめにする")
    func detachInterrupts() async throws {
        let bridge = ReviewRequestBridge()
        bridge.attachHost()
        let task = Task { await bridge.requestReview(for: moment) }
        try await waitUntil { bridge.pendingID != nil }
        bridge.detachHost()
        #expect(await task.value == .abandoned(.interrupted))
        #expect(!bridge.hasHost)
    }

    @Test("同じ依頼を2回終えても、2回目は何もしない")
    func resolveIsIdempotent() async throws {
        let bridge = ReviewRequestBridge()
        bridge.attachHost()
        let task = Task { await bridge.requestReview(for: moment) }
        try await waitUntil { bridge.pendingID != nil }
        let id = try #require(bridge.pendingID)
        bridge.resolve(id, with: .abandoned(.obstructed))
        bridge.resolve(id, with: .requested)
        #expect(await task.value == .abandoned(.obstructed))
    }

    @Test("メールのアプリが開けばメールに渡したとし、開かなければ失敗にする")
    func mailSender() async throws {
        let mail = FeedbackMail(recipient: "support@example.com",
                                labels: .init(subjects: [:], fallbackSubject: "Feedback", replyTo: "Reply to",
                                              diagnostics: "Diagnostics"))
        let feedback = try FeedbackDraft(text: "Hello").validated()

        var opened: [URL] = []
        let accepting = MailFeedbackSender(mail: mail, openURL: OpenURLAction { url in
            opened.append(url)
            return .handled
        })
        #expect(try await accepting.send(feedback) == .handedToMail)
        #expect(opened.first?.scheme == "mailto")

        let refusing = MailFeedbackSender(mail: mail, openURL: OpenURLAction { _ in .discarded })
        await #expect(throws: FeedbackError.noMailClient) { try await refusing.send(feedback) }
    }

    private let feedbackMail = FeedbackMail(
        recipient: "support@example.com",
        labels: .init(subjects: [:], fallbackSubject: "Feedback", replyTo: "Reply to", diagnostics: "Diagnostics")
    )

    @Test("作成画面の送り口は、受ける画面が無ければメールを開けない失敗にする")
    func composerWithoutHost() async throws {
        let sender = MailComposerFeedbackSender(mail: feedbackMail)
        let feedback = try FeedbackDraft(text: "Hello").validated()
        await #expect(throws: FeedbackError.noMailClient) { try await sender.send(feedback) }
    }

    @Test("作成画面の送り口は、添付ごと画面に渡し、画面の結果を返す")
    func composerCarriesAttachmentToHost() async throws {
        let sender = MailComposerFeedbackSender(mail: feedbackMail)
        sender.attachHost()
        let png = FeedbackAttachment(filename: "s.png", contentType: "image/png", data: Data([1, 2, 3]))
        let feedback = try FeedbackDraft(text: "Hello", attachments: [png]).validated()
        let task = Task { try await sender.send(feedback) }
        try await waitUntil { sender.pendingID != nil }
        #expect(sender.pendingFeedback?.attachments == [png])

        sender.resolve(try #require(sender.pendingID), with: .success(.handedToMail))
        #expect(try await task.value == .handedToMail)
        #expect(sender.pendingID == nil)
    }

    @Test("作成画面を閉じたら、送らずに取りやめた失敗にする")
    func composerDetachCancels() async throws {
        let sender = MailComposerFeedbackSender(mail: feedbackMail)
        sender.attachHost()
        let feedback = try FeedbackDraft(text: "Hello").validated()
        let task = Task { try await sender.send(feedback) }
        try await waitUntil { sender.pendingID != nil }
        sender.detachHost()
        await #expect(throws: FeedbackError.cancelled) { try await task.value }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}
