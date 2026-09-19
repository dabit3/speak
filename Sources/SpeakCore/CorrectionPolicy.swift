import Foundation

public enum CorrectionPolicy {
    public static let maximumCharacters = 4000

    public static func isEligible(_ text: String) -> Bool {
        text.count <= maximumCharacters && words(text).count >= 3 && !text.contains("`")
    }

    public static func accept(_ original: String, candidate: String, keywords: [String] = []) -> String? {
        let corrected = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty, corrected.count <= maximumCharacters else { return nil }
        if corrected == original { return original }
        guard isEligible(original), !corrected.contains("```"),
              protectedLiterals(original) == protectedLiterals(corrected),
              protectedWords(original) == protectedWords(corrected) else { return nil }
        let preface = #"(?i)^(?:sure[,!:]|here(?:'s| is)\b|(?:corrected(?: transcript| text)?|transcript)\s*:)"#
        if matches(preface, in: original).isEmpty && !matches(preface, in: corrected).isEmpty { return nil }
        let sourceWords = words(original)
        let resultWords = words(corrected)
        let resultNames = resultWords.map(normalize)
        let starters = Set("please the a an can could would should do does did we you they he she it this that these those let let's when where what why how if for in on at to send tell make add remove update use open close merge deploy push run create fix change check".split(separator: " ").map(String.init))
        for (index, word) in sourceWords.enumerated() {
            if word.count > 1 && word.first?.isUppercase == true && (index > 0 || !starters.contains(normalize(word))) {
                guard resultNames.contains(normalize(word)) else { return nil }
            }
        }
        for keyword in keywords {
            let pattern = "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: keyword) + "(?![\\p{L}\\p{N}])"
            if !matches(pattern, in: original).isEmpty && matches(pattern, in: corrected).isEmpty { return nil }
        }
        let limit = max(2, min(8, sourceWords.count / 5))
        guard editDistance(sourceWords.map(normalize), resultNames, limit: limit) <= limit else { return nil }
        return corrected
    }

    private static func words(_ text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { word, _, _, _ in
            if let word { result.append(word) }
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

    private static func protectedLiterals(_ text: String) -> [String] {
        matches(#"https?://[^\s]+|[\w.+-]+@[\w.-]+\.[\w]+|"[^"\n]*"|“[^”\n]*”|`[^`]*`|(?<![\p{L}\p{N}])[+-]?\p{N}+(?:[.,:/-]\p{N}+)*(?:%|\b)|\b[\p{L}_][\p{L}\p{N}]*[_./][\p{L}\p{N}_./-]+|--[\w-]+|\b[a-z]+[A-Z][\p{L}\p{N}]*\b|\b[A-Z]{2,}[A-Za-z0-9]*\b"#, in: text)
    }

    private static func protectedWords(_ text: String) -> [String] {
        matches(#"(?i)\b(?:no|not|never|neither|nor|without|cannot|can't|won't|don't|doesn't|didn't|isn't|aren't|wasn't|weren't|shouldn't|wouldn't|couldn't|mustn't|haven't|hasn't|hadn't|zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|today|tomorrow|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december)\b"#, in: normalize(text))
    }

    private static func editDistance(_ source: [String], _ result: [String], limit: Int) -> Int {
        guard abs(source.count - result.count) <= limit else { return limit + 1 }
        var previous = Array(0...result.count)
        for (i, word) in source.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: result.count)
            for (j, other) in result.enumerated() {
                current[j + 1] = min(current[j] + 1, previous[j + 1] + 1, previous[j] + (word == other ? 0 : 1))
            }
            if current.min()! > limit { return limit + 1 }
            previous = current
        }
        return previous.last!
    }
}
