import Foundation
import Testing
import ReviewCore
import ReviewTesting

@Suite("要望: 下書きの検査・診断の情報・送り口")
struct FeedbackTests {

    private let diagnostics = FeedbackDiagnostics([
        .init("app_version", "1.4.0 (120)"),
        .init("os", "iOS 26.0"),
        .init("recent_errors", "sync_failed@2026-09-30T10:00")
    ])

    private let mail = FeedbackMail(
        recipient: "support@example.com",
        labels: .init(
            subjects: [.bug: "不具合の報告", .request: "アプリへの要望"],
            fallbackSubject: "アプリについて",
            replyTo: "返信用のメール",
            diagnostics: "診断の情報"
        )
    )

    @Test("本文が空か空白だけなら送れない", arguments: ["", "   ", "\n\t"])
    func emptyText(text: String) {
        #expect(throws: FeedbackError.emptyText) { try FeedbackDraft(text: text).validated() }
    }

    @Test("本文は上限の文字数まで。前後の空白は除いて数える")
    func textLimit() throws {
        let limits = FeedbackLimits(maximumTextLength: 5)
        #expect(try FeedbackDraft(text: "  あいうえお \n").validated(limits: limits).text == "あいうえお")
        #expect(throws: FeedbackError.textTooLong(limit: 5)) {
            try FeedbackDraft(text: "あいうえおか").validated(limits: limits)
        }
    }

    @Test("返信用のメールは任意。入れたら形を見る")
    func replyAddress() throws {
        #expect(try FeedbackDraft(text: "x").validated().replyAddress == nil)
        #expect(try FeedbackDraft(text: "x", replyAddress: " a@example.com ").validated().replyAddress?.rawValue
            == "a@example.com")
        for bad in ["a", "a@", "@example.com", "a@example", "a b@example.com", "a@@example.com", "a@example."] {
            #expect(throws: FeedbackError.invalidReplyAddress) {
                try FeedbackDraft(text: "x", replyAddress: bad).validated()
            }
        }
    }

    @Test("診断の情報は既定でオフで、オフなら送る中身に入らない")
    func diagnosticsAreOptIn() throws {
        let draft = FeedbackDraft(kind: .bug, text: "落ちる", availableDiagnostics: diagnostics)
        #expect(!draft.includesDiagnostics)
        #expect(draft.diagnosticsPreview.isEmpty)
        #expect(try draft.validated().diagnostics == nil)
    }

    @Test("診断の情報をオンにすると、表示した行と同じものを送る")
    func previewIsWhatIsSent() throws {
        var draft = FeedbackDraft(kind: .bug, text: "落ちる", availableDiagnostics: diagnostics)
        draft.includesDiagnostics = true
        let feedback = try draft.validated()
        #expect(draft.diagnosticsPreview == ["app_version: 1.4.0 (120)", "os: iOS 26.0",
                                             "recent_errors: sync_failed@2026-09-30T10:00"])
        #expect(feedback.diagnostics?.lines == draft.diagnosticsPreview)
        #expect(mail.body(for: feedback).contains(draft.diagnosticsPreview.joined(separator: "\n")))
    }

    @Test("添付は枚数と大きさの上限まで")
    func attachmentLimits() {
        let png = FeedbackAttachment(filename: "s.png", contentType: "image/png", data: Data(count: 10))
        #expect(throws: FeedbackError.tooManyAttachments(limit: 1)) {
            try FeedbackDraft(text: "x", attachments: [png, png]).validated()
        }
        #expect(throws: FeedbackError.attachmentTooLarge(limit: 5)) {
            try FeedbackDraft(text: "x", attachments: [png]).validated(limits: FeedbackLimits(maximumAttachmentBytes: 5))
        }
    }

    @Test("メールのリンクは宛先・件名・本文を入れ、+ や & も崩さない")
    func mailLink() throws {
        let feedback = try FeedbackDraft(kind: .bug, text: "1+1 & 2?", replyAddress: "a+b@example.com").validated()
        let url = try mail.url(for: feedback)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == "support@example.com")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["subject"] == "不具合の報告")
        #expect(items["body"] == "1+1 & 2?\n\n返信用のメール: a+b@example.com")
        #expect(!url.absoluteString.contains("+"))
    }

    @Test("件名の無い種類は、既定の件名にする")
    func fallbackSubject() throws {
        let url = try mail.url(for: FeedbackDraft(kind: .other, text: "x").validated())
        #expect(url.absoluteString.contains("subject=%E3%82%A2%E3%83%97%E3%83%AA%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6"))
    }

    @Test("メールのリンクは添付を運べないので、添付があれば作らない")
    func mailRefusesAttachments() throws {
        let png = FeedbackAttachment(filename: "s.png", contentType: "image/png", data: Data([1, 2, 3]))
        let feedback = try FeedbackDraft(text: "x", attachments: [png]).validated()
        #expect(throws: FeedbackError.attachmentsUnsupported) { try mail.url(for: feedback) }
    }

    @Test("添付を外すと決めたときだけ、添付のあるものからもメールのリンクを作る")
    func mailOmitsAttachmentsWhenAsked() throws {
        let png = FeedbackAttachment(filename: "s.png", contentType: "image/png", data: Data([1, 2, 3]))
        let feedback = try FeedbackDraft(text: "x", attachments: [png]).validated()
        let url = try mail.url(for: feedback, omittingAttachments: true)
        #expect(url.scheme == "mailto")
        #expect(feedback.attachments.count == 1)
    }

    @Test("HTTP の送り口は JSON を POST し、同意の無い診断の情報は載せない")
    func httpRequestShape() throws {
        let sender = HTTPFeedbackSender(endpoint: URL(string: "https://api.example.com/v1/feedback")!,
                                        headers: ["Authorization": "Bearer t"]) { _ in
            throw URLError(.notConnectedToInternet)
        }
        let feedback = try FeedbackDraft(kind: .request, text: "地図がほしい", availableDiagnostics: diagnostics).validated()
        let request = try sender.request(for: feedback)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["kind"] as? String == "request")
        #expect(body?["text"] as? String == "地図がほしい")
        #expect(body?["diagnostics"] == nil)
        #expect(body?["replyAddress"] == nil)
    }

    @Test("HTTP の送り口は添付を base64 で載せる")
    func httpAttachments() throws {
        let png = FeedbackAttachment(filename: "s.png", contentType: "image/png", data: Data([0xFF, 0x00]))
        let payload = try FeedbackPayload(FeedbackDraft(text: "x", attachments: [png]).validated()).encoded()
        let body = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        let attachment = (body?["attachments"] as? [[String: String]])?.first
        #expect(attachment == ["filename": "s.png", "contentType": "image/png", "data": "/wA="])
    }

    @Test("HTTP の送り口は 2xx を届いたとし、それ以外は理由を付けて失敗にする")
    func httpStatuses() async throws {
        let feedback = try FeedbackDraft(text: "x").validated()
        func sender(status: Int) -> HTTPFeedbackSender {
            HTTPFeedbackSender(endpoint: URL(string: "https://api.example.com/v1/feedback")!) { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                               headerFields: ["Location": "/v1/feedback/42"])!
                return (Data(), response)
            }
        }
        #expect(try await sender(status: 201).send(feedback) == .delivered(receipt: "/v1/feedback/42"))
        await #expect(throws: FeedbackError.rejected(status: 429)) { try await sender(status: 429).send(feedback) }

        let offline = HTTPFeedbackSender(endpoint: URL(string: "https://api.example.com")!) { _ in
            throw URLError(.notConnectedToInternet)
        }
        await #expect {
            try await offline.send(feedback)
        } throws: { error in
            if case .transportFailed = error as? FeedbackError { return true }
            return false
        }
    }

    @Test("記録するだけの送り口は、渡されたものを順に持ち、決めた答えを返す")
    func recordingSender() async throws {
        let sender = RecordingFeedbackSender(answering: .success(.queued))
        let feedback = try FeedbackDraft(text: "x").validated()
        #expect(try await sender.send(feedback) == .queued)
        #expect(sender.sent == [feedback])
    }

    @Test("要望の計測は、種類・診断の有無・送った道だけを載せる")
    func feedbackMetric() {
        let event = ReviewMetricEvent.feedbackSent(kind: .bug, includesDiagnostics: true, delivery: .handedToMail)
        #expect(event.name == "feedback_sent")
        #expect(event.parameters == ["kind": .text("bug"), "diagnostics": .flag(true), "channel": .text("mail")])
        #expect(ReviewMetricEvent.feedbackSent(kind: .request, includesDiagnostics: false, delivery: .queued)
            .parameters["channel"] == .text("server"))
    }
}
