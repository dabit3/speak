import Foundation
import NaturalLanguage

public enum CorrectionPolicy {
    public static let maximumCharacters = 4000

    public static func isEligible(_ text: String) -> Bool {
        text.count <= maximumCharacters && words(text).count >= 3 && !text.contains("`")
    }

    public static func revisesItself(_ text: String, keywords: [String] = []) -> Bool {
        let text = normalize(TranscriptLiterals.hiding(in: text, keywords: keywords))
        return revisionCues.contains { !matches($0, in: text).isEmpty }
    }

    public static func accept(_ original: String, candidate: String, keywords: [String] = []) -> String? {
        let corrected = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty, corrected.count <= maximumCharacters else { return nil }
        if corrected == original { return original }
        guard isEligible(original), !corrected.contains("```") else { return nil }
        let preface = #"(?i)^(?:sure[,!:]|here(?:'s| is)\b|(?:corrected(?: transcript| text)?|transcript)\s*:)"#
        if matches(preface, in: original).isEmpty && !matches(preface, in: corrected).isEmpty { return nil }
        let revising = revisesItself(original, keywords: keywords)
        let breaks = matches(#"\n+"#, in: original.replacingOccurrences(of: "\r\n", with: "\n"))
        if !revising, !breaks.isEmpty, breaks != matches(#"\n+"#, in: corrected.replacingOccurrences(of: "\r\n", with: "\n")) { return nil }
        let source = DictationFormatter.canonicalNumbers(original, keywords: keywords), result = DictationFormatter.canonicalNumbers(corrected, keywords: keywords)
        let sourceValues = numericValues(source), resultValues = numericValues(result)
        let terms = Set(keywords.map(normalize))
        guard revising ? isSubsequence(resultValues, of: sourceValues) : resultValues == sourceValues,
              fits(protectedLiterals(corrected, terms: terms), within: protectedLiterals(original, terms: terms), exactly: !revising),
              fits(protectedWords(corrected), within: protectedWords(original), exactly: !revising) else { return nil }
        let sourceWords = words(original)
        if revising {
            let known = Set((sourceWords + keywords.flatMap(words)).map(normalize))
            guard names(in: corrected).allSatisfy({ known.contains(normalize($0)) }) else { return nil }
        } else {
            let tags = nameTags(in: original)
            let resultWords = Set(words(corrected).map(normalize))
            var added = resultWords.subtracting(sourceWords.map(normalize))
            for name in names(in: original, tags: tags) where !resultWords.contains(normalize(name)) {
                let person = tags[normalize(name)] == .personalName
                guard let spelling = added.first(where: { terms.contains($0) || (!person && respells(normalize(name), $0)) }) else { return nil }
                added.remove(spelling)
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

    private static func names(in text: String, tags: [String: NLTag] = [:]) -> [String] {
        var result: [String] = []
        var cursor = text.startIndex
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { word, range, _, _ in
            defer { cursor = range.upperBound }
            guard let word, word.count > 1, word.first?.isUppercase == true, !word.hasPrefix("I'"), !word.hasPrefix("I’"), !isAbbreviation(word) else { return }
            let opensSentence = cursor == text.startIndex || text[cursor..<range.lowerBound].contains(where: { ".!?\n".contains($0) })
            if !opensSentence || tags[normalize(word)] != nil { result.append(word) }
        }
        return result
    }

    private static func nameTags(in text: String) -> [String: NLTag] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var result: [String: NLTag] = [:]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) { result[normalize(String(text[range]))] = tag }
            return true
        }
        return result
    }

    private static func respells(_ name: String, _ word: String) -> Bool {
        let a = Array(name), b = Array(word)
        guard min(a.count, b.count) >= 5 else { return false }
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, y) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count] <= (max(a.count, b.count) >= 8 ? 2 : 1)
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

    private static func protectedLiterals(_ text: String, terms: Set<String> = []) -> [String] {
        matches(#"https?://[^\s]+|[\w.+-]+@[\w.-]+\.[\w]+|"[^"\n]*"|“[^”\n]*”|`[^`]*`|\b[\p{L}_][\p{L}\p{N}]*[_./][\p{L}\p{N}_./-]+|--[\w-]+|\b[a-z]+[A-Z][\p{L}\p{N}]*\b|\b[A-Z]{2,}[A-Za-z0-9]*\b"#, in: text)
            .filter { !isAbbreviation($0) }
            .map { terms.contains(normalize($0)) ? normalize($0) : $0 }
    }

    private static func isAbbreviation(_ text: String) -> Bool {
        ["am", "pm", "eg", "ie"].contains(normalize(text).replacingOccurrences(of: ".", with: ""))
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

    private static func isSubsequence(_ part: [String], of whole: [String]) -> Bool {
        var remaining = whole.makeIterator()
        return part.allSatisfy { value in
            while let next = remaining.next() { if next == value { return true } }
            return false
        }
    }

    private static let units: [String: String] = {
        let groups = [
            ["$", "dollar", "dollars"], ["€", "euro", "euros"], ["£"], ["¥", "yen"], ["cent", "cents"], ["pound", "pounds"], ["bucks"],
            ["%", "percent"], ["min", "minute", "minutes", "mins"], ["hr", "hour", "hours", "hrs"], ["sec", "second", "seconds", "secs"], ["s"], ["m"], ["h"],
            ["ms", "millisecond", "milliseconds"], ["day", "days"], ["week", "weeks"], ["month", "months"], ["year", "years"],
            ["decade", "decades"], ["mile", "miles"], ["km", "kilometer", "kilometers", "kilometre", "kilometres"],
            ["meter", "meters", "metre", "metres"], ["ft", "foot", "feet"], ["inch", "inches"], ["yard", "yards"],
            ["lb", "lbs"], ["kg", "kilo", "kilos", "kilogram", "kilograms"], ["g", "gram", "grams"], ["mg", "milligram", "milligrams"],
            ["oz", "ounce", "ounces"], ["liter", "liters", "litre", "litres"], ["gallon", "gallons"], ["degree", "degrees"],
            ["gb", "gigabyte", "gigabytes", "gigs"], ["mb", "megabyte", "megabytes"], ["kb", "kilobyte", "kilobytes"],
            ["tb", "terabyte", "terabytes"], ["mph"], ["times"]
        ]
        return Dictionary(uniqueKeysWithValues: groups.flatMap { group in group.map { ($0, group[0]) } })
    }()
    private static let unitNames = units.keys.sorted { $0.count > $1.count }
    private static let quantities: NSRegularExpression = {
        let number = #"[+\-−]?(?:[$€£¥][ \t]*)?[+\-−]?(?:\d+(?:,\d{3})*(?:[.:/]\d+)*|\.\d+)"#
        let scale = #"(?:[ \t]+(?:thousand|million|billion|trillion)\b)?"#
        let suffix = #"(?:[ \t]*(?:%|[$€£¥]|a\.?m\.?\b|p\.?m\.?\b)|[ \t]*(?:"# + unitNames.map(NSRegularExpression.escapedPattern).joined(separator: "|") + #")\b)?"#
        return try! NSRegularExpression(pattern: number + scale + suffix, options: .caseInsensitive)
    }()

    private static func numericValues(_ text: String) -> [String] {
        let string = text as NSString
        return quantities.matches(in: text, range: NSRange(location: 0, length: string.length)).map { match in
            var value = normalize(string.substring(with: match.range)).filter { !$0.isWhitespace && $0 != "," }
                .replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: "a.m", with: "am")
                .replacingOccurrences(of: "p.m", with: "pm")
            if value.hasSuffix(".") { value.removeLast() }
            for unit in unitNames where value.hasSuffix(unit) {
                let amount = String(value.dropLast(unit.count)), normalized = units[unit]!
                value = "$€£¥".contains(normalized) ? (amount.contains(normalized) ? amount : normalized + amount) : amount + normalized
                break
            }
            for symbol in ["$", "€", "£", "¥"] { value = value.replacingOccurrences(of: "-" + symbol, with: symbol + "-") }
            return value.replacingOccurrences(of: #"(?<![\d.])\.(?=\d)"#, with: "0.", options: .regularExpression)
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
