import AppKit
import Combine
import Security
import LocalAuthentication
import SpeakCore

enum PillPosition: String, CaseIterable, Identifiable {
    case bottom, left, right
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    @Published var delay: TranscriptionDelay { didSet { defaults.set(delay.rawValue, forKey: "delay") } }
    @Published var vocabulary: String { didSet { defaults.set(vocabulary, forKey: "vocabulary") } }
    @Published var shortcut: String { didSet { defaults.set(shortcut, forKey: "shortcut") } }
    @Published var showPill: Bool { didSet { defaults.set(showPill, forKey: "showPill") } }
    @Published var pillPosition: PillPosition { didSet { defaults.set(pillPosition.rawValue, forKey: "pillPosition") } }
    @Published var smartCorrectionEnabled: Bool { didSet { defaults.set(smartCorrectionEnabled, forKey: "smartCorrectionEnabled") } }
    @Published var showLiveTranscript: Bool { didSet { defaults.set(showLiveTranscript, forKey: "showLiveTranscript") } }
    @Published var hasAPIKey = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, checkKeychain: Bool = true) {
        self.defaults = defaults
        language = defaults.string(forKey: "language") ?? "en"
        delay = TranscriptionDelay(rawValue: defaults.string(forKey: "delay") ?? "low") ?? .low
        vocabulary = defaults.string(forKey: "vocabulary") ?? ""
        shortcut = defaults.string(forKey: "shortcut") ?? "fn"
        showPill = defaults.object(forKey: "showPill") as? Bool ?? true
        pillPosition = PillPosition(rawValue: defaults.string(forKey: "pillPosition") ?? "") ?? .bottom
        smartCorrectionEnabled = defaults.object(forKey: "smartCorrectionEnabled") as? Bool ?? true
        showLiveTranscript = defaults.object(forKey: "showLiveTranscript") as? Bool ?? true
        hasAPIKey = checkKeychain && KeychainStore.hasKey
    }

    var shortcutLabel: String { shortcut == "fn" ? "fn" : "⌃ ⌥" }
    var configuration: TranscriptionConfiguration {
        .init(language: language, delay: delay, vocabulary: vocabulary)
    }

    func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else {
            throw DictationError("Enter a valid OpenAI API key.")
        }
        try KeychainStore.save(trimmed)
        hasAPIKey = true
    }
}

enum KeychainStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.speak.dictation",
        kSecAttrAccount as String: "openai-api-key"
    ]

    static var hasKey: Bool {
        var lookup = query
        lookup[kSecReturnAttributes as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        lookup[kSecUseAuthenticationContext as String] = context
        return SecItemCopyMatching(lookup as CFDictionary, nil) == errSecSuccess
    }

    static func read() throws -> String {
        var lookup = query
        lookup[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw DictationError("Could not read your API key. Save it again in Preferences and allow Keychain access.")
        }
        return key
    }

    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw DictationError("Could not save the API key in Keychain (\(status)).") }
        } else if update != errSecSuccess {
            throw DictationError("Could not update the API key in Keychain (\(update)).")
        }
    }
}
