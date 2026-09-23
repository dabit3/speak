import Foundation

enum SpokenNumbers {
    enum Style { case display, canonical }

    static let units = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9]
    static let teens = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19
    ]
    static let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
    static let scales = ["thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000, "trillion": 1_000_000_000_000]
    static let ordinals = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9,
        "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15, "sixteenth": 16,
        "seventeenth": 17, "eighteenth": 18, "nineteenth": 19, "twentieth": 20, "thirtieth": 30, "fortieth": 40,
        "fiftieth": 50, "sixtieth": 60, "seventieth": 70, "eightieth": 80, "ninetieth": 90, "hundredth": 100,
        "thousandth": 1_000, "millionth": 1_000_000
    ]
    static let months: Set<String> = [
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"
    ]
    static let measures: Set<String> = [
        "percent", "dollars", "dollar", "cents", "cent", "euros", "euro", "pounds", "yen", "bucks", "minutes", "minute", "mins",
        "min", "hours", "hour", "hrs", "hr", "seconds", "second", "secs", "sec", "milliseconds", "ms", "days", "day", "weeks",
        "week", "months", "month", "years", "year", "decades", "times", "miles", "mile", "kilometers", "kilometres", "km",
        "meters", "metres", "feet", "foot", "ft", "inches", "inch", "yards", "lbs", "kilos", "kilograms", "kg", "grams",
        "ounces", "oz", "liters", "litres", "gallons", "degrees", "gb", "mb", "kb", "tb", "gigabytes", "megabytes",
        "terabytes", "gigs", "mph"
    ]
    static let labels: Set<String> = [
        "version", "step", "page", "chapter", "section", "part", "room", "level", "floor", "gate", "track", "episode",
        "season", "option", "item", "line", "row", "column", "phase", "stage", "grade", "figure", "table", "slide", "task",
        "ticket", "issue", "bug", "pr", "apartment", "unit", "suite", "route", "highway", "exhibit", "appendix", "volume",
        "act", "scene", "tier", "size", "rule", "article", "game", "round", "ios", "macos", "iphone", "python", "swift"
    ]
    static let plurals: Set<String> = [
        "hundreds", "thousands", "millions", "billions", "trillions", "dozens", "teens", "twenties", "thirties", "forties",
        "fifties", "sixties", "seventies", "eighties", "nineties"
    ]
    static let clockWords: Set<String> = ["at", "by", "around", "until", "till", "til", "from", "before", "after", "since", "it's"]

    static func apply(to pieces: inout [Piece], style: Style) {
        var scanner = Scanner(pieces: pieces.flatMap(expand), style: style)
        scanner.run()
        pieces = scanner.pieces
    }

    private static func expand(_ piece: Piece) -> [Piece] {
        let parts = piece.core.split(separator: "-").map(String.init)
        guard parts.count == 2, tens[parts[0].lowercased()] != nil else { return [piece] }
        let second = parts[1].lowercased()
        guard second != "second", units[second].map({ $0 > 0 }) ?? (ordinals[second].map { $0 < 10 } ?? false) else { return [piece] }
        return [
            Piece(gap: piece.gap, lead: piece.lead, core: parts[0], trail: ""),
            Piece(gap: " ", lead: "", core: parts[1], trail: piece.trail)
        ]
    }

    static func grouped(_ value: Int) -> String {
        let digits = String(value)
        var result = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0 && (digits.count - offset) % 3 == 0 { result.append(",") }
            result.append(digit)
        }
        return result
    }

    static func suffix(_ value: Int) -> String {
        if (11...13).contains(value % 100) { return "th" }
        switch value % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    private struct Parsed {
        var value: Int
        var end: Int
        var ordinal: Bool
        var scale: Int?
        var article: Bool
    }

    private struct Scanner {
        var pieces: [Piece]
        let style: Style

        private enum Kind { case none, article, unit, teen, tens, tensUnit, hundred, scale, and }

        mutating func run() {
            var index = 0
            while index < pieces.count {
                if let (range, text) = match(at: index) {
                    pieces.replace(range, with: text)
                    index = range.lowerBound + 1
                } else {
                    index += 1
                }
            }
        }

        private func word(_ index: Int) -> String { pieces.word(index) }
        private func connects(_ index: Int) -> Bool { pieces.connects(index) }
        private func next(after end: Int) -> String { connects(end - 1) ? word(end) : "" }

        private func match(at index: Int) -> (ClosedRange<Int>, String)? {
            if let date = date(at: index) { return date }
            if style == .display, pieces[index].core.first?.isUppercase == true, !pieces.startsSentence(index) { return nil }
            if let (end, text) = clock(at: index) { return (index...(end - 1), text) }
            if let (value, end) = year(at: index) { return (index...(end - 1), String(value)) }
            if let (end, digits) = digitRun(at: index) { return (index...(end - 1), digits) }
            if word(index) == "negative", connects(index), let (end, text) = quantity(at: index + 1, forced: true) {
                return (index...(end - 1), "-" + text)
            }
            if let (end, text) = quantity(at: index, forced: false) { return (index...(end - 1), text) }
            return nil
        }

        private func cardinal(at start: Int) -> Parsed? {
            var total = 0, group = 0, largest = Int.max, kind = Kind.none, result: Parsed?
            var index = start
            scan: while index < pieces.count, index == start || connects(index - 1) {
                let current = word(index)
                if current == "second", kind == .tens, word(start - 1) != "the", !SpokenNumbers.months.contains(start > 0 ? pieces[start - 1].core : "") { break }
                if current == "a", kind == .none, SpokenNumbers.scales[word(index + 1)] != nil || word(index + 1) == "hundred", connects(index) {
                    group = 1
                    kind = .article
                    index += 1
                    continue
                }
                if current == "and" {
                    guard kind == .hundred || kind == .scale, connects(index), let value = small(word(index + 1)), value < 100 else { break }
                    kind = .and
                    index += 1
                    continue
                }
                let ordinal = SpokenNumbers.ordinals[current]
                guard let value = SpokenNumbers.units[current] ?? SpokenNumbers.teens[current] ?? SpokenNumbers.tens[current]
                        ?? (current == "hundred" ? 100 : nil) ?? SpokenNumbers.scales[current] ?? ordinal else { break }
                let open: Set<Kind> = [.none, .hundred, .scale, .and]
                switch value {
                case 0:
                    guard kind == .none else { break scan }
                    kind = .unit
                case 1...9:
                    guard open.contains(kind) || kind == .tens else { break scan }
                    group += value
                    kind = kind == .tens ? .tensUnit : .unit
                case 10...90:
                    guard open.contains(kind) else { break scan }
                    group += value
                    kind = value < 20 ? .teen : .tens
                case 100:
                    guard [.unit, .teen, .tens, .tensUnit, .article].contains(kind), (1...99).contains(group) else { break scan }
                    group *= 100
                    kind = .hundred
                default:
                    guard [.unit, .teen, .tens, .tensUnit, .hundred, .article].contains(kind), group > 0, value < largest else { break scan }
                    total += group * value
                    group = 0
                    largest = value
                    kind = .scale
                }
                result = Parsed(value: total + group, end: index + 1, ordinal: ordinal != nil, scale: kind == .scale ? largest : nil, article: word(start) == "a")
                index += 1
                if ordinal != nil || value == 0 { break }
            }
            return result
        }

        private func small(_ word: String) -> Int? {
            SpokenNumbers.units[word].flatMap { $0 > 0 ? $0 : nil } ?? SpokenNumbers.teens[word] ?? SpokenNumbers.tens[word]
                ?? SpokenNumbers.ordinals[word].flatMap { $0 < 100 ? $0 : nil }
        }

        private func year(at index: Int) -> (Int, Int)? {
            let first = word(index)
            guard let century = SpokenNumbers.teens[first].flatMap({ $0 >= 13 ? $0 : nil }) ?? (first == "twenty" ? 20 : nil),
                  connects(index) else { return nil }
            let second = word(index + 1)
            let value: Int, end: Int
            if let decade = SpokenNumbers.tens[second] {
                if connects(index + 1), let unit = SpokenNumbers.units[word(index + 2)], unit > 0 {
                    (value, end) = (century * 100 + decade + unit, index + 3)
                } else {
                    (value, end) = (century * 100 + decade, index + 2)
                }
            } else if let teen = SpokenNumbers.teens[second] {
                (value, end) = (century * 100 + teen, index + 2)
            } else if second == "oh" || second == "o", connects(index + 1), let unit = SpokenNumbers.units[word(index + 2)], unit > 0 {
                (value, end) = (century * 100 + unit, index + 3)
            } else {
                return nil
            }
            let after = next(after: end)
            guard !SpokenNumbers.measures.contains(after), !SpokenNumbers.plurals.contains(after), after != "hundred",
                  SpokenNumbers.scales[after] == nil else { return nil }
            return (value, end)
        }

        private func clock(at index: Int) -> (Int, String)? {
            let first = word(index)
            guard let hour = (SpokenNumbers.units[first] ?? SpokenNumbers.teens[first] ?? Int(first)).flatMap({ (1...12).contains($0) ? $0 : nil })
            else { return nil }
            let spokenHour = pieces[index].core.first?.isLetter == true
            var end = index + 1, minutes: Int?, spoken = spokenHour, spokenMinutes = false
            if connects(index), let (value, after, isSpoken) = minute(at: index + 1) {
                (minutes, end, spokenMinutes) = (value, after, isSpoken)
                spoken = spoken || isSpoken
            }
            guard spoken else { return nil }
            let time = minutes.map { "\(hour):" + String(format: "%02d", $0) } ?? "\(hour)"
            let suffix = next(after: end)
            if ["am", "a.m", "pm", "p.m"].contains(suffix), !(suffix == "am" && word(end + 1) == "i") {
                let core = pieces[end].core
                return (end + 1, time + " " + (core.contains(".") ? core.lowercased() : core.uppercased()))
            }
            if minutes == nil, suffix == "o'clock" { return (end + 1, "\(hour) o'clock") }
            if minutes != nil, SpokenNumbers.clockWords.contains(index > 0 && connects(index - 1) ? word(index - 1) : "") { return (end, time) }
            if let minutes, [15, 30, 45].contains(minutes), spokenHour, spokenMinutes, !SpokenNumbers.measures.contains(suffix),
               !SpokenNumbers.plurals.contains(suffix), SpokenNumbers.scales[suffix] == nil, suffix != "hundred" { return (end, time) }
            return nil
        }

        private func minute(at index: Int) -> (Int, Int, Bool)? {
            let current = word(index)
            if ["oh", "o", "zero"].contains(current), connects(index), let unit = SpokenNumbers.units[word(index + 1)], unit > 0 {
                return (unit, index + 2, true)
            }
            if let teen = SpokenNumbers.teens[current] { return (teen, index + 1, true) }
            if let decade = SpokenNumbers.tens[current], decade <= 50 {
                if connects(index), let unit = SpokenNumbers.units[word(index + 1)], unit > 0 { return (decade + unit, index + 2, true) }
                return (decade, index + 1, true)
            }
            if current.count == 2, let value = Int(current), value < 60 { return (value, index + 1, false) }
            return nil
        }

        private func date(at index: Int) -> (ClosedRange<Int>, String)? {
            guard SpokenNumbers.months.contains(pieces[index].core), connects(index) else { return nil }
            let start = index + 1
            var day: Int, end: Int, spoken: Bool, ordinal: Bool
            if let parsed = cardinal(at: start), (1...31).contains(parsed.value), !parsed.article {
                (day, end, spoken, ordinal) = (parsed.value, parsed.end, true, parsed.ordinal)
            } else if let match = word(start).wholeMatch(of: #/(\d{1,2})(st|nd|rd|th)?/#), let value = Int(match.1), (1...31).contains(value) {
                (day, end, spoken, ordinal) = (value, start + 1, false, match.2 != nil)
            } else {
                return nil
            }
            var text = String(day), last = end - 1, dated = false
            if end < pieces.count, pieces[end].lead.isEmpty, pieces[end].gap == " ", ["", ","].contains(pieces[end - 1].trail) {
                if let (value, after) = year(at: end) {
                    (text, last, dated, spoken) = (text + ", \(value)", after - 1, true, true)
                } else if let parsed = cardinal(at: end), (1000...2999).contains(parsed.value), !parsed.ordinal {
                    (text, last, dated, spoken) = (text + ", \(parsed.value)", parsed.end - 1, true, true)
                }
            }
            guard spoken, ordinal || dated else { return nil }
            return (start...last, text)
        }

        private func digitRun(at index: Int) -> (Int, String)? {
            guard SpokenNumbers.units[word(index)] != nil else { return nil }
            var digits = "", end = index
            while end < pieces.count, end == index || connects(end - 1), let digit = digit(word(end)) {
                digits += digit
                end += 1
            }
            return digits.count >= 3 ? (end, digits) : nil
        }

        private func digit(_ word: String) -> String? {
            SpokenNumbers.units[word].map(String.init) ?? (word == "oh" || word == "o" ? "0" : nil)
        }

        private func fraction(after end: Int) -> (String, Int)? {
            guard ["point", "dot"].contains(next(after: end)), connects(end) else { return nil }
            var digits = "", index = end + 1
            if let parsed = cardinal(at: index), (10...99).contains(parsed.value), !parsed.ordinal {
                (digits, index) = (String(parsed.value), parsed.end)
            } else if word(index).allSatisfy(\.isNumber), !word(index).isEmpty {
                (digits, index) = (word(index), index + 1)
            } else {
                while index < pieces.count, index == end + 1 || connects(index - 1), let digit = digit(word(index)) {
                    digits += digit
                    index += 1
                }
            }
            guard !digits.isEmpty else { return nil }
            if let (more, after) = fraction(after: index) { return ("." + digits + more, after) }
            return ("." + digits, index)
        }

        private func quantity(at index: Int, forced: Bool) -> (Int, String)? {
            var parsed: Parsed?, text: String, end: Int, spoken = true
            let core = pieces[index].core
            if core.first?.isNumber == true, core.last?.isNumber == true, core.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }) {
                (text, end, spoken) = (core, index + 1, false)
            } else if let value = cardinal(at: index) {
                (parsed, text, end) = (value, render(value, grouping: 10_000), value.end)
            } else {
                return nil
            }
            if let parsed, parsed.ordinal { return ordinal(parsed, at: index) }
            if SpokenNumbers.plurals.contains(next(after: end)) { return nil }
            var decimal = false
            if parsed?.scale == nil, !text.contains("."), let (digits, after) = fraction(after: end) {
                (text, end, decimal, spoken) = (text.replacingOccurrences(of: ",", with: "") + digits, after, true, true)
                if let scale = SpokenNumbers.scales[next(after: end)], scale >= 1_000_000 {
                    text += " " + word(end)
                    end += 1
                }
            }
            let following = next(after: end)
            if following == "percent" { return (end + 1, text + "%") }
            if following == "per", connects(end), word(end + 1) == "cent" { return (end + 2, text + "%") }
            if following == "dollars" || following == "dollar" {
                var amount = decimal ? text : parsed.map { render($0, grouping: 1_000) } ?? text
                var last = end + 1
                if !decimal, parsed?.scale == nil, !amount.contains("."), connects(end) {
                    let start = word(end + 1) == "and" && connects(end + 1) ? end + 2 : end + 1
                    if let cents = cardinal(at: start), cents.value < 100, !cents.ordinal, ["cents", "cent"].contains(next(after: cents.end)) {
                        amount += "." + String(format: "%02d", cents.value)
                        last = cents.end + 1
                    }
                }
                return (last, "$" + amount)
            }
            guard spoken else { return nil }
            guard let parsed, !decimal else { return (end, text) }
            return forced || shouldWrite(parsed, at: index) ? (end, text) : nil
        }

        private func shouldWrite(_ parsed: Parsed, at index: Int) -> Bool {
            if style == .canonical { return true }
            if parsed.article { return parsed.end - index > 2 }
            if parsed.value >= 10 { return true }
            if SpokenNumbers.labels.contains(index > 0 && connects(index - 1) ? word(index - 1) : "") { return true }
            let following = next(after: parsed.end)
            if SpokenNumbers.measures.contains(following) { return word(index) != "one" }
            return measured(after: parsed.end)
        }

        private func measured(after end: Int) -> Bool {
            let following = next(after: end)
            if SpokenNumbers.measures.contains(following) { return true }
            guard ["or", "to", "and"].contains(following), connects(end), let parsed = cardinal(at: end + 1), !parsed.ordinal else { return false }
            return measured(after: parsed.end)
        }

        private func ordinal(_ parsed: Parsed, at index: Int) -> (Int, String)? {
            let month = next(after: parsed.end) == "of" && connects(parsed.end) && parsed.end + 1 < pieces.count
                && SpokenNumbers.months.contains(pieces[parsed.end + 1].core)
            guard style == .canonical || parsed.value >= 10 || month else { return nil }
            return (parsed.end, "\(parsed.value)\(SpokenNumbers.suffix(parsed.value))")
        }

        private func render(_ parsed: Parsed, grouping: Int) -> String {
            if let scale = parsed.scale, scale >= 1_000_000, parsed.value % scale == 0, parsed.value / scale < 1000,
               let name = SpokenNumbers.scales.first(where: { $0.value == scale })?.key {
                return "\(parsed.value / scale) \(name)"
            }
            return parsed.value >= grouping ? SpokenNumbers.grouped(parsed.value) : String(parsed.value)
        }
    }
}
