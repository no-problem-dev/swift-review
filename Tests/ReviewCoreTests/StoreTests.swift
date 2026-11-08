import Foundation
import Testing
import ReviewCore

@Suite("状態の置き場所")
struct StoreTests {

    /// A suite of its own per test, so parallel tests never share stored state.
    private func makeStore() -> (UserDefaultsReviewStateStore, String) {
        let suite = "swift-review.tests.\(UUID().uuidString)"
        return (UserDefaultsReviewStateStore(suiteName: suite)!, suite)
    }

    @Test("何も保存していなければ nil を返す")
    func emptyLoadsNil() throws {
        let (store, _) = makeStore()
        #expect(try store.load() == nil)
    }

    @Test("保存した状態を読み戻し、消すと nil に戻る")
    func saveLoadClear() throws {
        let (store, _) = makeStore()
        let state = Fixture.eligibleState()
        try store.save(state)
        #expect(try store.load() == state)
        store.clear()
        #expect(try store.load() == nil)
    }

    @Test("同じ suite の名前なら、別の値から作っても同じ状態を読む")
    func sameSuiteSameState() throws {
        let (store, suite) = makeStore()
        try store.save(Fixture.eligibleState())
        #expect(try UserDefaultsReviewStateStore(suiteName: suite)!.load() == Fixture.eligibleState())
    }

    @Test("キーにデータ以外が入っていれば、壊れた状態として扱う")
    func nonDataIsCorrupt() throws {
        let (store, suite) = makeStore()
        UserDefaults(suiteName: suite)!.set("hello", forKey: "review.state")
        #expect(throws: ReviewStoreError.corrupt) { try store.load() }
    }

    @Test("UserDefaults が断る suite の名前では作らない")
    func refusedSuiteName() {
        #expect(UserDefaultsReviewStateStore(suiteName: "NSGlobalDomain") == nil)
    }

    @Test("渡した UserDefaults のインスタンスに書き、同じ suite から読める")
    func instanceWritesToTheGivenDefaults() throws {
        let suite = "swift-review.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = UserDefaultsReviewStateStore(defaults: defaults)
        try store.save(Fixture.eligibleState())
        #expect(defaults.data(forKey: "review.state") != nil)
        #expect(try UserDefaultsReviewStateStore(suiteName: suite)!.load() == Fixture.eligibleState())
        store.clear()
        #expect(defaults.object(forKey: "review.state") == nil)
    }

    @Test("インスタンスでもキーを変えられ、別のキーには触れない")
    func instanceHonorsKey() throws {
        let defaults = try #require(UserDefaults(suiteName: "swift-review.tests.\(UUID().uuidString)"))
        let store = UserDefaultsReviewStateStore(defaults: defaults, key: "other.key")
        try store.save(Fixture.eligibleState())
        #expect(defaults.object(forKey: "review.state") == nil)
        #expect(try UserDefaultsReviewStateStore(defaults: defaults, key: "other.key").load() == Fixture.eligibleState())
    }

    @Test("インスタンスの置き場所は Sendable のまま別のタスクから使える")
    func instanceIsSendable() async throws {
        let defaults = try #require(UserDefaults(suiteName: "swift-review.tests.\(UUID().uuidString)"))
        let store = UserDefaultsReviewStateStore(defaults: defaults)
        try await Task.detached { try store.save(Fixture.eligibleState()) }.value
        #expect(try store.load() == Fixture.eligibleState())
    }

    @Test("前からの書き方（引数なし・キーだけ）はそのまま作れる")
    func existingCallsStillCompile() {
        let stores: [any ReviewStateStore] = [
            UserDefaultsReviewStateStore(),
            UserDefaultsReviewStateStore(key: "review.state")
        ]
        #expect(stores.count == 2)
    }

    @Test("メモリの置き場所も、本物と同じ保存の形を通る")
    func inMemoryUsesTheStoredForm() throws {
        let store = try InMemoryReviewStateStore(Fixture.eligibleState())
        #expect(try store.load() == Fixture.eligibleState())
        #expect(throws: ReviewStoreError.newerSchema(found: 5, supported: 1)) {
            try InMemoryReviewStateStore(storedData: Data(#"{"schema":5}"#.utf8)).load()
        }
    }
}
