import Foundation
import Testing
import ReviewCore

@Suite("状態: 記録・整理・保存の形")
struct ReviewStateTests {

    private func sample() -> ReviewState {
        ReviewState(
            installedAt: Fixture.now.addingTimeInterval(-Fixture.days(30)),
            activeDays: [ReviewDay("2026-09-30")!, ReviewDay("2026-10-01")!],
            signals: [ReviewSignal(Fixture.movementDecided, in: Fixture.tripA, at: Fixture.now)],
            blockers: [ReviewBlocker(Fixture.paywallDismissed, at: Fixture.now)],
            asks: [ReviewAsk(at: Fixture.now, version: Fixture.v1_0, moment: Fixture.journalSaved, scope: Fixture.tripA)]
        )
    }

    @Test("保存の形を往復しても同じ状態に戻る")
    func roundTrip() throws {
        let state = sample()
        #expect(try ReviewState.decode(state.encoded()) == state)
    }

    @Test("保存の形には版の番号が入る")
    func storedFormCarriesSchema() throws {
        let object = try JSONSerialization.jsonObject(with: sample().encoded()) as? [String: Any]
        #expect(object?["schema"] as? Int == ReviewState.schemaVersion)
        #expect(object?["activeDays"] as? [String] == ["2026-09-30", "2026-10-01"])
    }

    @Test("知らない項目は残して書き戻す")
    func unknownFieldsSurvive() throws {
        var object = try JSONSerialization.jsonObject(with: sample().encoded()) as! [String: Any]
        object["futureField"] = ["nested": [1, 2, 3]]
        let data = try JSONSerialization.data(withJSONObject: object)

        var state = try ReviewState.decode(data)
        state.record(ReviewSignal(Fixture.stayAdded, in: Fixture.tripA, at: Fixture.now))
        let written = try JSONSerialization.jsonObject(with: state.encoded()) as? [String: Any]
        #expect((written?["futureField"] as? [String: [Int]])?["nested"] == [1, 2, 3])
        #expect((written?["signals"] as? [Any])?.count == 2)
    }

    @Test("新しい版の保存の形は読まない")
    func newerSchemaIsRefused() {
        let data = Data(#"{"schema": 2, "activeDays": [], "signals": [], "blockers": [], "asks": []}"#.utf8)
        #expect(throws: ReviewStoreError.newerSchema(found: 2, supported: 1)) { try ReviewState.decode(data) }
    }

    @Test("状態でない中身は読まない", arguments: [
        "not json",
        "[]",
        #"{"activeDays": []}"#,
        #"{"schema": 1, "activeDays": ["2026-02-30"], "signals": [], "blockers": [], "asks": []}"#,
        #"{"schema": 1, "activeDays": [], "signals": [], "blockers": [], "asks": [{"at": 0, "version": "1.x", "moment": "m"}]}"#
    ])
    func corruptIsRefused(text: String) {
        #expect(throws: ReviewStoreError.corrupt) { try ReviewState.decode(Data(text.utf8)) }
    }

    @Test("止める出来事は、種類と範囲ごとに最後の時刻だけを持つ")
    func blockersKeepTheLatestPerKindAndScope() {
        var state = ReviewState()
        state.record(ReviewBlocker(Fixture.error, at: Fixture.now))
        state.record(ReviewBlocker(Fixture.error, at: Fixture.now.addingTimeInterval(-60)))
        state.record(ReviewBlocker(Fixture.error, in: Fixture.tripA, at: Fixture.now.addingTimeInterval(-30)))
        state.record(ReviewBlocker(Fixture.error, at: Fixture.now.addingTimeInterval(60)))
        #expect(state.blockers.count == 2)
        #expect(state.blockers.first { $0.scope == nil }?.at == Fixture.now.addingTimeInterval(60))
    }

    @Test("取り消しは、その種類と範囲の最後の合図を1つだけ消す")
    func retractRemovesOnlyTheLatest() {
        var state = ReviewState()
        state.record(ReviewSignal(Fixture.movementDecided, in: Fixture.tripA, at: Fixture.now.addingTimeInterval(-60)))
        state.record(ReviewSignal(Fixture.movementDecided, in: Fixture.tripA, at: Fixture.now))
        state.record(ReviewSignal(Fixture.movementDecided, in: Fixture.tripB, at: Fixture.now.addingTimeInterval(60)))

        let removed = state.retract(Fixture.movementDecided, in: Fixture.tripA)
        #expect(removed)
        #expect(state.signals.map(\.at) == [Fixture.now.addingTimeInterval(-60), Fixture.now.addingTimeInterval(60)])
        let nothing = state.retract(Fixture.stayAdded, in: Fixture.tripA)
        #expect(!nothing)
    }

    @Test("範囲を忘れると、その範囲の合図と止める出来事が消え、頼んだ記録は残る")
    func forgetScope() {
        var state = sample()
        state.record(ReviewBlocker(Fixture.tripDisrupted, in: Fixture.tripA, at: Fixture.now))
        state.forget(Fixture.tripA)
        #expect(state.signals.isEmpty)
        #expect(state.blockers.map(\.kind) == [Fixture.paywallDismissed])
        #expect(state.asks.count == 1)
    }

    @Test("整理は、もう答えを変えない記録だけを落とす")
    func pruneDropsOnlyWhatCannotMatter() {
        let policy = Fixture.policy()
        var state = ReviewState()
        state.record(ReviewSignal(Fixture.movementDecided, at: Fixture.now.addingTimeInterval(-Fixture.days(400))))
        state.record(ReviewSignal(Fixture.stayAdded, at: Fixture.now.addingTimeInterval(-Fixture.days(10))))
        state.record(ReviewBlocker(Fixture.error, at: Fixture.now.addingTimeInterval(-Fixture.days(4))))
        state.record(ReviewBlocker(Fixture.paywallDismissed, at: Fixture.now.addingTimeInterval(-Fixture.days(4))))
        state.record(ReviewBlocker(Fixture.tripDisrupted, in: Fixture.tripA, at: Fixture.now.addingTimeInterval(-Fixture.days(200))))
        state.record(ReviewBlocker("no_cooldown", at: Fixture.now))
        state.record(ReviewAsk(at: Fixture.now.addingTimeInterval(-Fixture.days(700)), version: Fixture.v1_0, moment: Fixture.journalSaved))
        state.record(ReviewAsk(at: Fixture.now.addingTimeInterval(-Fixture.days(500)), version: Fixture.v1_1, moment: Fixture.journalSaved))
        state.record(ReviewAsk(at: Fixture.now.addingTimeInterval(-Fixture.days(450)), version: Fixture.v1_1, moment: Fixture.journalSaved))
        state.record(ReviewAsk(at: Fixture.now.addingTimeInterval(-Fixture.days(100)), version: Fixture.v1_2, moment: Fixture.journalSaved))

        state.prune(at: Fixture.now, policy: policy)

        #expect(state.signals.map(\.kind) == [Fixture.stayAdded])
        #expect(Set(state.blockers.map(\.kind)) == [Fixture.paywallDismissed, Fixture.tripDisrupted])
        #expect(state.asks.map(\.version) == [Fixture.v1_0, Fixture.v1_1, Fixture.v1_2])
        #expect(state.asks.first { $0.version == Fixture.v1_1 }?.at == Fixture.now.addingTimeInterval(-Fixture.days(450)))
    }

    @Test("整理の後も、1年より前に頼んだ版では頼まない")
    func pruningKeepsTheVersionRule() {
        let policy = Fixture.policy()
        var state = Fixture.eligibleState()
            .adding(ReviewAsk(at: Fixture.now.addingTimeInterval(-Fixture.days(500)), version: Fixture.v1_0,
                              moment: Fixture.journalSaved))
        #expect(Fixture.decide(state: state) == .skip(.alreadyAskedThisVersion(Fixture.v1_0)))
        state.prune(at: Fixture.now, policy: policy)
        #expect(Fixture.decide(state: state) == .skip(.alreadyAskedThisVersion(Fixture.v1_0)))
    }
}

@Suite("日付と版の値")
struct ValueTests {

    @Test("日付は YYYY-MM-DD で読み書きし、無い日は作らない")
    func reviewDayText() {
        #expect(ReviewDay("2026-10-01")?.description == "2026-10-01")
        #expect(ReviewDay(year: 7, month: 3, day: 9)?.description == "0007-03-09")
        #expect(ReviewDay("2026-02-29") == nil)
        #expect(ReviewDay("2028-02-29") != nil)
        #expect(ReviewDay("1900-02-29") == nil)
        #expect(ReviewDay("2000-02-29") != nil)
        #expect(ReviewDay("2026-1-01") == nil)
        #expect(ReviewDay("２０２６-10-01") == nil)
    }

    @Test("日付の差は日数で数え、年をまたいでも合う")
    func reviewDayArithmetic() {
        let start = ReviewDay("2026-12-30")!
        #expect(start.days(to: ReviewDay("2027-01-02")!) == 3)
        #expect(ReviewDay("2028-03-01")!.days(to: ReviewDay("2028-02-28")!) == -2)
        #expect(ReviewDay("1970-01-01")!.days(to: ReviewDay("2000-01-01")!) == 10_957)
    }

    @Test("日付にできない時刻からは作らない")
    func reviewDayFromInvalidInstant() {
        #expect(ReviewDay(Date(timeIntervalSince1970: .nan), in: Fixture.tokyo) == nil)
        #expect(ReviewDay(Date(timeIntervalSince1970: -70_000_000_000), in: Fixture.tokyo) == nil)
        #expect(ReviewDay(Date(timeIntervalSince1970: .infinity), in: Fixture.tokyo) == nil)
    }

    @Test("版は1〜3個の数で読み、足りない所は0にする", arguments: [
        ("2", AppVersion(major: 2)),
        ("2.1", AppVersion(major: 2, minor: 1)),
        ("2.1.3", AppVersion(major: 2, minor: 1, patch: 3)),
        ("10.0.12", AppVersion(major: 10, minor: 0, patch: 12))
    ])
    func appVersionParses(text: String, expected: AppVersion) {
        #expect(AppVersion(text) == expected)
    }

    @Test("比べられない版は作らない", arguments: ["", "1.", "1..2", "1.2b", "1.2.3.4", "v1.2", "-1.0", " 1.2"])
    func appVersionRejects(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test("版は数として比べ、単位で切り捨てる")
    func appVersionOrdering() {
        #expect(AppVersion("1.10")! > AppVersion("1.9")!)
        #expect(AppVersion("1.4.3")!.truncated(to: .minor) == AppVersion("1.4")!)
        #expect(AppVersion("1.4.3")!.truncated(to: .major) == AppVersion("1")!)
        #expect(AppVersion("1.4.3")!.truncated(to: .patch) == AppVersion("1.4.3")!)
    }

    @Test("版は文字列として保存する")
    func appVersionCodable() throws {
        let data = try JSONEncoder().encode([AppVersion("1.4.3")!])
        #expect(String(decoding: data, as: UTF8.self) == #"["1.4.3"]"#)
        #expect(try JSONDecoder().decode([AppVersion].self, from: data) == [AppVersion("1.4.3")!])
    }

    @Test("書く画面のリンクは action=write-review を付けた App Store の URL")
    func writeReviewLink() {
        let id = AppStoreID("1585901351")!
        #expect(WriteReviewLink.url(for: id).absoluteString == "https://apps.apple.com/app/id1585901351?action=write-review")
    }

    @Test("仮の値や空の値は App Store の ID にしない", arguments: ["", "APP_STORE_ID", "id123", "12 34", "１２３"])
    func appStoreIDRejectsPlaceholders(text: String) {
        #expect(AppStoreID(text) == nil)
    }
}
