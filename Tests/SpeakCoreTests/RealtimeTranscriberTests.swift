import XCTest
@testable import SpeakCore

final class MockSocket: TranscriptionSocket, @unchecked Sendable {
    actor Storage {
        var sent: [[String: Any]] = []
        var queued: [Data] = []
        var waiting: CheckedContinuation<Data, Error>?
        var closed = false
        let completes: Bool
        let fails: Bool

        init(completes: Bool, fails: Bool, greets: Bool) {
            self.completes = completes
            self.fails = fails
            if greets { queued = [Data("{\"type\":\"session.created\"}".utf8)] }
        }

        func push(_ event: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: event)
            if let waiting {
                self.waiting = nil
                waiting.resume(returning: data)
            } else { queued.append(data) }
        }

        func send(_ text: String) throws {
            if closed { throw URLError(.networkConnectionLost) }
            let event = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
            sent.append(event)
            switch event["type"] as? String {
            case "session.update":
                try push(["type": "session.updated"])
            case "input_audio_buffer.append":
                if fails {
                    try push(["type": "error", "error": ["code": "insufficient_quota"]])
                } else {
                    try push(["type": "conversation.item.input_audio_transcription.delta", "item_id": "one", "delta": "Hello"])
                }
            case "input_audio_buffer.commit":
                try push(["type": "input_audio_buffer.committed", "item_id": "one"])
                if completes {
                    try push(["type": "conversation.item.input_audio_transcription.completed", "item_id": "one", "transcript": "Hello, world."])
                }
            default: break
            }
        }

        func receive() async throws -> Data {
            if closed { throw URLError(.networkConnectionLost) }
            if !queued.isEmpty { return queued.removeFirst() }
            return try await withCheckedThrowingContinuation { waiting = $0 }
        }

        func close() {
            closed = true
            waiting?.resume(throwing: URLError(.networkConnectionLost))
            waiting = nil
        }

        func eventTypes() -> [String] { sent.compactMap { $0["type"] as? String } }
        func audioBytes() -> Int {
            sent.compactMap { $0["audio"] as? String }.compactMap { Data(base64Encoded: $0)?.count }.reduce(0, +)
        }
    }

    let storage: Storage
    init(completes: Bool = true, fails: Bool = false, greets: Bool = true) {
        storage = Storage(completes: completes, fails: fails, greets: greets)
    }
    func send(_ text: String) async throws { try await storage.send(text) }
    func receive() async throws -> Data { try await storage.receive() }
    func close() { Task { await storage.close() } }
}

final class RealtimeTranscriberTests: XCTestCase {
    private let configuration = TranscriptionConfiguration(language: "en", delay: .low, vocabulary: "")

    @MainActor func testAudioIsSentInOrderAndCommittedOnce() async throws {
        let socket = MockSocket()
        let client = RealtimeTranscriber(socket: socket)
        let audio = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 1, count: 4800))
            continuation.yield(Data(repeating: 2, count: 4800))
            continuation.finish()
        }
        var ready = false
        var partials: [String] = []
        let text = try await client.transcribe(audio: audio, configuration: configuration, onReady: { ready = true }, onPartial: { partials.append($0) })
        XCTAssertTrue(ready)
        XCTAssertEqual(text, "Hello, world.")
        XCTAssertFalse(partials.isEmpty)
        let events = await socket.storage.eventTypes()
        let bytes = await socket.storage.audioBytes()
        XCTAssertEqual(events, ["session.update", "input_audio_buffer.append", "input_audio_buffer.append", "input_audio_buffer.commit"])
        XCTAssertEqual(bytes, 9600)
    }

    @MainActor func testShortRecordingDoesNotCommit() async {
        let socket = MockSocket()
        let client = RealtimeTranscriber(socket: socket)
        let audio = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 0, count: 200))
            continuation.finish()
        }
        do {
            _ = try await client.transcribe(audio: audio, configuration: configuration, onReady: {}, onPartial: { _ in })
            XCTFail("Short recording must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("too short")) }
        let events = await socket.storage.eventTypes()
        XCTAssertFalse(events.contains("input_audio_buffer.commit"))
    }

    @MainActor func testServerFailureCancelsAnOpenAudioStream() async {
        let socket = MockSocket(fails: true)
        let client = RealtimeTranscriber(socket: socket)
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        pair.continuation.yield(Data(repeating: 0, count: 4800))
        do {
            _ = try await client.transcribe(audio: pair.stream, configuration: configuration, onReady: {}, onPartial: { _ in })
            XCTFail("Server failure must not become a transcript")
        } catch { XCTAssertTrue(error.localizedDescription.contains("usage limit")) }
        pair.continuation.finish()
        let events = await socket.storage.eventTypes()
        XCTAssertFalse(events.contains("input_audio_buffer.commit"))
    }

    @MainActor func testFinishBeforeHandshakeRetainsTheFinalDeadline() async {
        let socket = MockSocket(completes: false)
        let client = RealtimeTranscriber(socket: socket, finalTimeout: 1)
        client.finishSoon()
        let audio = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 0, count: 4800))
            continuation.finish()
        }
        do {
            _ = try await client.transcribe(audio: audio, configuration: configuration, onReady: {}, onPartial: { _ in })
            XCTFail("Missing final transcript must time out")
        } catch { XCTAssertTrue(error.localizedDescription.contains("final transcript took too long")) }
    }

    @MainActor func testConnectionTimeout() async {
        let socket = MockSocket(greets: false)
        let client = RealtimeTranscriber(socket: socket, connectionTimeout: 0)
        let audio = AsyncThrowingStream<Data, Error> { $0.finish() }
        do {
            _ = try await client.transcribe(audio: audio, configuration: configuration, onReady: {}, onPartial: { _ in })
            XCTFail("Missing greeting must time out")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Could not connect")) }
    }

    @MainActor func testCancellationNeverCommits() async {
        let socket = MockSocket()
        let client = RealtimeTranscriber(socket: socket)
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        let task = Task {
            try await client.transcribe(audio: pair.stream, configuration: configuration, onReady: { client.cancel() }, onPartial: { _ in })
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled session must not complete")
        } catch { XCTAssertTrue(error is CancellationError) }
        pair.continuation.finish()
        let events = await socket.storage.eventTypes()
        XCTAssertFalse(events.contains("input_audio_buffer.commit"))
    }
}
