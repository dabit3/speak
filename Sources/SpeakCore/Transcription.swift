import Foundation

public enum TranscriptionDelay: String, CaseIterable, Identifiable {
    case minimal, low, medium, high, xhigh
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .minimal: return "Fastest"
        case .low: return "Fast"
        case .medium: return "Balanced"
        case .high: return "More context"
        case .xhigh: return "Most context"
        }
    }
}

public struct TranscriptionConfiguration {
    public static let endpoint = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!
    public static let model = "gpt-live-transcribe"
    public static let prompt = "Dictated messages, emails, notes, and documents written on a computer. The speaker may mention names, products, technical terms, numbers, dates, times, prices, and email addresses."
    public let language: String
    public let delay: TranscriptionDelay
    public let vocabulary: String

    public init(language: String, delay: TranscriptionDelay, vocabulary: String) {
        self.language = language
        self.delay = delay
        self.vocabulary = vocabulary
    }

    public var keywords: [String] {
        var seen = Set<String>()
        return vocabulary.components(separatedBy: CharacterSet(charactersIn: ",\n\r"))
            .map { $0.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(100).map { String($0.prefix(100)) }
    }

    public func sessionMessage() throws -> Data {
        var transcription: [String: Any] = ["model": Self.model, "delay": delay.rawValue, "prompt": Self.prompt]
        if !language.isEmpty { transcription["languages"] = [language] }
        if !keywords.isEmpty { transcription["keywords"] = keywords }
        return try JSONSerialization.data(withJSONObject: [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": ["input": [
                    "format": ["type": "audio/pcm", "rate": 24000],
                    "transcription": transcription,
                    "noise_reduction": ["type": "near_field"],
                    "turn_detection": NSNull()
                ]]
            ]
        ])
    }
}

public struct DictationError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public struct TranscriptAccumulator {
    public private(set) var partial = ""
    public private(set) var committedItem: String?
    private var completed: [String: String] = [:]
    private var deltas: [String: String] = [:]

    public init() {}

    public mutating func consume(_ event: [String: Any]) throws -> String? {
        let type = event["type"] as? String ?? ""
        let item = event["item_id"] as? String ?? ""
        switch type {
        case "input_audio_buffer.committed":
            committedItem = item
        case "conversation.item.input_audio_transcription.delta":
            deltas[item, default: ""] += event["delta"] as? String ?? ""
            if committedItem == nil || committedItem == item { partial = deltas[item] ?? "" }
        case "conversation.item.input_audio_transcription.completed":
            completed[item] = event["transcript"] as? String ?? ""
        case "error", "conversation.item.input_audio_transcription.failed":
            let error = event["error"] as? [String: Any]
            let code = error?["code"] as? String ?? ""
            if code == "invalid_api_key" {
                throw DictationError("Your API key was not accepted. Update it in Preferences.")
            }
            if code == "insufficient_quota" || code == "rate_limit_exceeded" {
                throw DictationError("OpenAI usage limit reached. Check your API billing or try again later.")
            }
            throw DictationError(error?["message"] as? String ?? "OpenAI could not transcribe this recording. Please try again.")
        default: break
        }
        guard let committedItem, let final = completed[committedItem] else { return nil }
        let trimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictationError("No speech was detected. Try speaking closer to your microphone.") }
        partial = trimmed
        return trimmed
    }
}
