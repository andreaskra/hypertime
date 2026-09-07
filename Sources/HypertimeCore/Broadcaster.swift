import Foundation

/// Fan-out of values to any number of `AsyncStream` consumers.
public final class Broadcaster<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]

    public init() {}

    /// A new, independent stream. Consumers may come and go at any time.
    public var stream: AsyncStream<Value> {
        AsyncStream { continuation in
            let id = add(continuation)
            continuation.onTermination = { [weak self] _ in self?.remove(id) }
        }
    }

    public func send(_ value: Value) {
        let all = lock.withLock { Array(continuations.values) }
        for continuation in all { continuation.yield(value) }
    }

    public func finish() {
        let all = lock.withLock { () -> [AsyncStream<Value>.Continuation] in
            let values = Array(continuations.values)
            continuations.removeAll()
            return values
        }
        for continuation in all { continuation.finish() }
    }

    private func add(_ continuation: AsyncStream<Value>.Continuation) -> UUID {
        let id = UUID()
        lock.withLock { continuations[id] = continuation }
        return id
    }

    private func remove(_ id: UUID) {
        lock.withLock { _ = continuations.removeValue(forKey: id) }
    }
}
