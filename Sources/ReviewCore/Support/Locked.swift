import os

/// A value behind an unfair lock, so a final class holding only `let`s of this type is `Sendable`
/// without vouching for it by hand.
///
/// `Mutex` would do the same but needs iOS 18 / macOS 15.
package final class Locked<Value: Sendable>: Sendable {

    private let lock: OSAllocatedUnfairLock<Value>

    package init(_ value: Value) {
        lock = OSAllocatedUnfairLock(initialState: value)
    }

    package var value: Value {
        lock.withLock { $0 }
    }

    @discardableResult
    package func withValue<Result: Sendable>(_ body: @Sendable (inout Value) -> Result) -> Result {
        lock.withLock { body(&$0) }
    }
}
