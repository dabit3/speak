import Foundation

public enum CorrectionLearner {
    static let maximumChangedTokens = 400

    public static func fixes(from original: String, to edited: String, isKnownWord: (String) -> Bool) -> [LearnedWord] {
        let source = words(original), result = words(edited)
        guard !source.isEmpty, !result.isEmpty, source != result, let changes = changes(source, result),
              changes.reduce(0, { $0 + $1.from.count }) <= max(4, source.count / 2) else { return [] }
        var fixes: [LearnedWord] = []
        for change in changes where !change.from.isEmpty && !change.to.isEmpty {
            let heard = Array(source[change.from]), meant = Array(result[change.to])
            let pairs = heard.count == meant.count ? zip(heard, meant).map { ([$0], [$1]) } : [(heard, meant)]
            for (heard, meant) in pairs {
                if let fix = fix(heard: heard, meant: meant, isKnownWord: isKnownWord), !fixes.contains(fix) { fixes.append(fix) }
            }
        }
        return fixes
    }

    static func fix(heard: [String], meant: [String], isKnownWord: (String) -> Bool) -> LearnedWord? {
        guard heard.count <= 3, meant.count <= 2, (heard + meant).allSatisfy(isWordLike) else { return nil }
        let from = heard.joined(separator: " "), term = meant.joined(separator: " ")
        let a = letters(from), b = letters(term)
        guard from != term else { return nil }
        if a == b, term == term.uppercased() || term == term.lowercased() { return nil }
        let similar = a == b || distance(a, b) <= max(1, max(a.count, b.count) * 2 / 5)
        guard similar || meant.contains(where: isDistinctive) else { return nil }
        let hint = meant.contains { isDistinctive($0) || !isKnownWord($0.lowercased()) }
        let replace = heard.contains { $0 != $0.uppercased() && !isKnownWord($0.lowercased()) && !isKnownWord($0.capitalized) }
        guard hint || replace else { return nil }
        return LearnedWord(term: term, replaces: replace ? [from] : [], isHint: hint)
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).compactMap { chunk in
            var token = Substring(chunk)
            while let first = token.first, !(first.isLetter || first.isNumber) { token.removeFirst() }
            while let last = token.last, !(last.isLetter || last.isNumber) { token.removeLast() }
            return token.isEmpty ? nil : String(token)
        }
    }

    static func changes(_ a: [String], _ b: [String]) -> [(from: Range<Int>, to: Range<Int>)]? {
        var prefix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let x = Array(a[prefix..<(a.count - suffix)]), y = Array(b[prefix..<(b.count - suffix)])
        guard x.count <= maximumChangedTokens, y.count <= maximumChangedTokens else { return nil }
        var table = [[Int]](repeating: [Int](repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            for j in stride(from: y.count - 1, through: 0, by: -1) {
                table[i][j] = x[i] == y[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [(from: Range<Int>, to: Range<Int>)] = []
        var i = 0, j = 0
        var start: (Int, Int)?
        while i < x.count || j < y.count {
            if i < x.count, j < y.count, x[i] == y[j] {
                if let start { result.append((prefix + start.0..<prefix + i, prefix + start.1..<prefix + j)) }
                start = nil
                i += 1
                j += 1
            } else {
                if start == nil { start = (i, j) }
                if j < y.count, i == x.count || table[i][j + 1] >= table[i + 1][j] { j += 1 } else { i += 1 }
            }
        }
        if let start { result.append((prefix + start.0..<prefix + x.count, prefix + start.1..<prefix + y.count)) }
        return result
    }

    static func isWordLike(_ token: String) -> Bool {
        token.count <= 30 && token.contains(where: \.isLetter)
            && token.allSatisfy { $0.isLetter || $0.isNumber || "'’-._+#&".contains($0) }
            && token.range(of: #"[\p{Han}\p{Hiragana}\p{Katakana}\p{Thai}]"#, options: .regularExpression) == nil
    }

    static func isDistinctive(_ token: String) -> Bool {
        token.dropFirst().contains(where: \.isUppercase) || (token.contains(where: \.isLetter) && token.contains(where: \.isNumber))
    }

    private static func letters(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, y) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
