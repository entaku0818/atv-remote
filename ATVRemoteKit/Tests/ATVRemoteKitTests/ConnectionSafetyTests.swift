import XCTest
@testable import ATVRemoteKit

final class ConnectionSafetyTests: XCTestCase {
    func testReplyBeforeWaitingIsRemembered() async throws {
        let signal = AsyncSignal()
        signal.resolve(.success(()))
        try await signal.wait(timeout: 0.01)
    }

    func testDuplicateCompletionKeepsFirstResult() async throws {
        let signal = AsyncSignal()
        signal.resolve(.success(()))
        signal.resolve(.failure(ATVError.timedOut))
        try await signal.wait()
    }

    func testNoReplyTimesOut() async {
        do {
            try await AsyncSignal().wait(timeout: 0.01)
            XCTFail("Missing reply must time out")
        } catch ATVError.timedOut {
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCancellationDoesNotWaitForTimeout() async {
        let signal = AsyncSignal()
        let task = Task { try await signal.wait(timeout: 60) }
        task.cancel()
        do {
            try await task.value
            XCTFail("Cancelled wait must fail")
        } catch is CancellationError {
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testOversizedFrameRejectedBeforeAllocatingPayload() {
        var framer = MessageFramer()
        XCTAssertThrowsError(try framer.append(Varint.encode(MessageFramer.maximumMessageSize + 1)))
    }

    func testMalformedLengthCannotOverflowOrGrowBufferForever() {
        XCTAssertNil(Varint.decode(Data(repeating: 0xFF, count: 10)))
        var framer = MessageFramer()
        XCTAssertThrowsError(try framer.append(Data(repeating: 0xFF, count: 10)))
    }
}
