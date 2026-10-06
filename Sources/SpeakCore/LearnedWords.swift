import Foundation

public struct LearnedWord: Codable, Hashable, Sendable {
    public var term: String
    public var replaces: [String]
    public var isHint: Bool

    public init(term: String, replaces: [String] = [], isHint: Bool = true) {
        self.term = term
        self.replaces = replaces
        self.isHint = isHint
    }
}

public struct LearnedWords: Codable, Equatable, Sendable {
    public static let capacity = 200
    public private(set) var words: [LearnedWord]

    public init(_ words: [LearnedWord] = []) {
        self.words = Array(words.prefix(Self.capacity))
    }

    public var isEmpty: Bool { words.isEmpty }
    public var hints: [String] { words.filter(\.isHint).map(\.term) }

    public mutating func learn(_ fixes: [LearnedWord]) {
        for fix in fixes.reversed() {
            let key = fix.term.lowercased()
            let heard = Set(fix.replaces.map { $0.lowercased() })
            var entry = words.first { $0.term.lowercased() == key } ?? LearnedWord(term: fix.term, isHint: false)
            words.removeAll { $0.term.lowercased() == key || heard.contains($0.term.lowercased()) }
            for index in words.indices { words[index].replaces.removeAll { $0.lowercased() == key } }
            words.removeAll { !$0.isHint && $0.replaces.isEmpty }
            entry.term = fix.term
            entry.isHint = entry.isHint || fix.isHint
            for form in fix.replaces where !entry.replaces.contains(where: { $0.lowercased() == form.lowercased() }) {
                entry.replaces.append(form)
            }
            words.insert(entry, at: 0)
        }
        if words.count > Self.capacity { words.removeLast(words.count - Self.capacity) }
    }

    public mutating func remove(_ word: LearnedWord) {
        words.removeAll { $0.term == word.term }
    }

    public func apply(to text: String) -> String {
        var replacements: [String: String] = [:]
        for word in words.reversed() {
            for form in word.replaces { replacements[Self.key(form)] = word.term }
        }
        guard !text.isEmpty, !replacements.isEmpty else { return text }
        let alternatives = replacements.keys.sorted { $0.count > $1.count }.map { form in
            form.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[\\p{Zs}\\t]+")
        }
        let pattern = "(?<![\\p{L}\\p{N}])(?:" + alternatives.joined(separator: "|") + ")(?![\\p{L}\\p{N}])"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        let string = text as NSString
        let literals = TranscriptLiterals.ranges(in: text)
        var result = ""
        var cursor = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            guard !literals.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
            let found = string.substring(with: match.range)
            guard var replacement = replacements[Self.key(found)] else { continue }
            if found.first?.isUppercase == true, let first = replacement.first, first.isLowercase {
                replacement = first.uppercased() + replacement.dropFirst()
            }
            result += string.substring(with: NSRange(location: cursor, length: match.range.location - cursor)) + replacement
            cursor = match.range.location + match.range.length
        }
        return result + string.substring(from: cursor)
    }

    private static func key(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
