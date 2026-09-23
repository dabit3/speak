import Foundation

public enum CorrectionPolicy {
    public static let maximumCharacters = 4000

    public static func isEligible(_ text: String) -> Bool {
        text.count <= maximumCharacters && words(text).count >= 3 && !text.contains("`")
    }

    public static func revisesItself(_ text: String) -> Bool {
        let text = normalize(text)
        return revisionCues.contains { !matches($0, in: text).isEmpty }
    }

    public static func accept(_ original: String, candidate: String, keywords: [String] = []) -> String? {
        let corrected = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty, corrected.count <= maximumCharacters else { return nil }
        if corrected == original { return original }
        guard isEligible(original), !corrected.contains("```") else { return nil }
        let preface = #"(?i)^(?:sure[,!:]|here(?:'s| is)\b|(?:corrected(?: transcript| text)?|transcript)\s*:)"#
        if matches(preface, in: original).isEmpty && !matches(preface, in: corrected).isEmpty { return nil }
        let revising = revisesItself(original)
        let source = DictationFormatter.canonicalNumbers(original), result = DictationFormatter.canonicalNumbers(corrected)
        let sourceDigits = source.filter(\.isNumber), resultDigits = result.filter(\.isNumber)
        guard revising ? isSubsequence(resultDigits, of: sourceDigits) : resultDigits == sourceDigits,
              fits(protectedLiterals(corrected), within: protectedLiterals(original), exactly: !revising),
              fits(protectedWords(corrected), within: protectedWords(original), exactly: !revising) else { return nil }
        let sourceWords = words(original)
        if revising {
            let known = Set((sourceWords + keywords.flatMap(words)).map(normalize))
            guard names(in: corrected).allSatisfy({ known.contains(normalize($0)) }) else { return nil }
        } else {
            let resultNames = Set(words(corrected).map(normalize))
            let starters = Set("please the a an can could would should do does did we you they he she it this that these those let let's when where what why how if for in on at to send tell make add remove update use open close merge deploy push run create fix change check".split(separator: " ").map(String.init))
            for (index, word) in sourceWords.enumerated() where word.count > 1 && word.first?.isUppercase == true && (index > 0 || !starters.contains(normalize(word))) {
                guard resultNames.contains(normalize(word)) else { return nil }
            }
            for keyword in keywords {
                let pattern = "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: keyword) + "(?![\\p{L}\\p{N}])"
                if !matches(pattern, in: original).isEmpty && matches(pattern, in: corrected).isEmpty { return nil }
            }
        }
        let limit = max(2, min(8, sourceWords.count / 5))
        let (added, removed) = changes(from: comparable(source), to: comparable(result))
        guard added <= limit, revising || removed <= limit else { return nil }
        return corrected
    }

    private static let revisionCues = [
        #"\b(?:scratch|strike|delete) that\b"#,
        #"\b(?:no|nope|oops|sorry|wait)[,.!]?\s+(?:no|wait|i mean|i meant|actually|rather)\b"#,
        #"[\p{L}\p{N}%][,;]?\s+(?:i mean|i meant|or rather)\b"#,
        #",\s*(?:actually|make that)\b"#,
        #",\s*(?:no|nope|wait|sorry|correction)[,.!:]\s"#
    ]

    private static let ignorable: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "comma", "period", "colon", "semicolon"]

    private static func words(_ text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { word, _, _, _ in
            if let word { result.append(word) }
        }
        return result
    }

    private static func names(in text: String) -> [String] {
        var result: [String] = []
        var cursor = text.startIndex
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { word, range, _, _ in
            defer { cursor = range.upperBound }
            guard let word, word.count > 1, word.first?.isUppercase == true, !word.hasPrefix("I'"), !word.hasPrefix("I’"),
                  cursor != text.startIndex, !text[cursor..<range.lowerBound].contains(where: { ".!?\n".contains($0) }) else { return }
            result.append(word)
        }
        return result
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let string = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: string.length)).map { string.substring(with: $0.range) }
    }

    private static func comparable(_ canonical: String) -> [String] {
        words(canonical.replacingOccurrences(of: #"(?<=\d),(?=\d{3})"#, with: "", options: .regularExpression))
            .map(normalize).filter { !ignorable.contains($0) }
    }

    private static func protectedLiterals(_ text: String) -> [String] {
        matches(#"https?://[^\s]+|[\w.+-]+@[\w.-]+\.[\w]+|"[^"\n]*"|“[^”\n]*”|`[^`]*`|\b[\p{L}_][\p{L}\p{N}]*[_./][\p{L}\p{N}_./-]+|--[\w-]+|\b[a-z]+[A-Z][\p{L}\p{N}]*\b|\b[A-Z]{2,}[A-Za-z0-9]*\b"#, in: text)
    }

    private static func protectedWords(_ text: String) -> [String] {
        matches(#"\b(?:no|not|never|neither|nor|without|cannot|\w+n't|today|tomorrow|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december)\b"#, in: normalize(text))
            .map { $0 == "cannot" || $0.hasSuffix("n't") ? "not" : $0 }
    }

    private static func fits(_ result: [String], within source: [String], exactly: Bool) -> Bool {
        if exactly { return result == source }
        var remaining = Dictionary(source.map { ($0, 1) }, uniquingKeysWith: +)
        for item in result {
            guard let count = remaining[item], count > 0 else { return false }
            remaining[item] = count - 1
        }
        return true
    }

    private static func isSubsequence(_ part: String, of whole: String) -> Bool {
        var remaining = whole.makeIterator()
        return part.allSatisfy { character in
            while let next = remaining.next() { if next == character { return true } }
            return false
        }
    }

    private static func changes(from source: [String], to result: [String]) -> (added: Int, removed: Int) {
        var previous = [Int](repeating: 0, count: result.count + 1)
        var current = previous
        for word in source {
            for (index, other) in result.enumerated() {
                current[index + 1] = word == other ? previous[index] + 1 : max(previous[index + 1], current[index])
            }
            swap(&previous, &current)
        }
        let common = previous[result.count]
        return (result.count - common, source.count - common)
    }
}
