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

    @Test("メモリの置き場所も、本物と同じ保存の形を通る")
    func inMemoryUsesTheStoredForm() throws {
        let store = try InMemoryReviewStateStore(Fixture.eligibleState())
        #expect(try store.load() == Fixture.eligibleState())
        #expect(throws: ReviewStoreError.newerSchema(found: 5, supported: 1)) {
            try InMemoryReviewStateStore(storedData: Data(#"{"schema":5}"#.utf8)).load()
        }
    }
}
