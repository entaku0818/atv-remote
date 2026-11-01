import Foundation

/// One-shot result that also remembers replies received before the waiter starts.
final class AsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?

    func resolve(_ result: Result<Void, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    func wait(timeout: TimeInterval = 15) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { pending in
                lock.lock()
                if let result {
                    lock.unlock()
                    pending.resume(with: result)
                } else {
                    continuation = pending
                    lock.unlock()
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                        self?.resolve(.failure(ATVError.timedOut))
                    }
                }
            }
        } onCancel: {
            self.resolve(.failure(CancellationError()))
        }
    }
}
