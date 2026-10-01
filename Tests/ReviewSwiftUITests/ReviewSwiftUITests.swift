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

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}
