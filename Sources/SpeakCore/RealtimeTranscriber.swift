import Foundation

public protocol TranscriptionSocket: AnyObject, Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> Data
    func close()
}

public final class OpenAIWebSocket: TranscriptionSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let session: URLSession

    public init(apiKey: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        session = URLSession(configuration: configuration)
        var request = URLRequest(url: TranscriptionConfiguration.endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        task = session.webSocketTask(with: request)
        task.resume()
    }

    public func send(_ text: String) async throws { try await task.send(.string(text)) }

    public func receive() async throws -> Data {
        switch try await task.receive() {
        case .data(let data): return data
        case .string(let text): return Data(text.utf8)
        @unknown default: throw DictationError("OpenAI returned an unreadable response.")
        }
    }

    public func close() {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

@MainActor
public final class RealtimeTranscriber {
    private let socket: any TranscriptionSocket
    private var deadline: Task<Void, Never>?
    private var timeoutMessage: String?
    private var cancelled = false
    private var finishing = false
    private let connectionTimeout: UInt64
    private let finalTimeout: UInt64

    public init(socket: any TranscriptionSocket, connectionTimeout: UInt64 = 12, finalTimeout: UInt64 = 20) {
        self.socket = socket
        self.connectionTimeout = connectionTimeout
        self.finalTimeout = finalTimeout
    }

    public func finishSoon() {
        finishing = true
        armDeadline(seconds: finalTimeout, message: "The final transcript took too long. Check your connection and try again.")
    }

    public func cancel() {
        cancelled = true
        deadline?.cancel()
        socket.close()
    }

    public func transcribe(
        audio: AsyncThrowingStream<Data, Error>,
        configuration: TranscriptionConfiguration,
        onReady: @escaping @MainActor () -> Void,
        onPartial: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        if deadline == nil {
            armDeadline(seconds: connectionTimeout, message: "Could not connect to OpenAI. Check your internet connection and API key.")
        }
        defer {
            deadline?.cancel()
            socket.close()
        }
        do {
            var accumulator = TranscriptAccumulator()
            while true {
                let event = try await receiveEvent()
                _ = try accumulator.consume(event)
                let type = event["type"] as? String
                if type == "session.created" || type == "transcription_session.created" { break }
            }
            try await socket.send(String(decoding: configuration.sessionMessage(), as: UTF8.self))
            while true {
                let event = try await receiveEvent()
                _ = try accumulator.consume(event)
                let type = event["type"] as? String
                if type == "session.updated" || type == "transcription_session.updated" { break }
            }
            if !finishing { deadline?.cancel() }
            onReady()
            return try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask { [socket] in
                    var bytes = 0
                    for try await chunk in audio {
                        try Task.checkCancellation()
                        bytes += chunk.count
                        let event: [String: Any] = ["type": "input_audio_buffer.append", "audio": chunk.base64EncodedString()]
                        try await socket.send(String(decoding: JSONSerialization.data(withJSONObject: event), as: UTF8.self))
                    }
                    try Task.checkCancellation()
                    guard bytes >= 4800 else { throw DictationError("That recording was too short. Hold the shortcut a little longer.") }
                    try await socket.send("{\"type\":\"input_audio_buffer.commit\"}")
                    return nil
                }
                group.addTask { [socket] in
                    var transcript = TranscriptAccumulator()
                    while true {
                        try Task.checkCancellation()
                        let data = try await socket.receive()
                        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let final = try transcript.consume(event) { return final }
                        if !transcript.partial.isEmpty { await onPartial(transcript.partial) }
                    }
                }
                defer {
                    group.cancelAll()
                    socket.close()
                }
                while let result = try await group.next() {
                    if let result { return result }
                }
                throw DictationError("The connection ended without a final transcript.")
            }
        } catch {
            if cancelled || Task.isCancelled { throw CancellationError() }
            if let timeoutMessage { throw DictationError(timeoutMessage) }
            if let error = error as? DictationError { throw error }
            throw DictationError("The transcription connection failed. Check your internet, API key, and access to GPT-Live-Transcribe.")
        }
    }

    private func receiveEvent() async throws -> [String: Any] {
        let data = try await socket.receive()
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DictationError("OpenAI returned an unreadable response.")
        }
        return event
    }

    private func armDeadline(seconds: UInt64, message: String) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            self?.timeoutMessage = message
            self?.socket.close()
        }
    }
}
