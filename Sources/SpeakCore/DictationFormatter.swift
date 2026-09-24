import Foundation

public enum DictationFormatter {
    public static func format(_ text: String, language: String = "en") -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard supports(language) else { return trimmed }
        var pieces = Piece.split(trimmed)
        applyCommands(&pieces)
        removeDisfluencies(&pieces)
        joinAddresses(&pieces)
        SpokenNumbers.apply(to: &pieces, style: .display)
        return Piece.join(pieces)
    }

    static func canonicalNumbers(_ text: String) -> String {
        var pieces = Piece.split(text)
        SpokenNumbers.apply(to: &pieces, style: .canonical)
        return Piece.join(pieces)
    }

    static func supports(_ language: String) -> Bool {
        language.isEmpty || language.lowercased().hasPrefix("en")
    }

    private enum Mark { case attach(String), lineBreak(String), open(String), close(String) }

    private static let commands: [(words: [String], mark: Mark)] = [
        (["question", "mark"], .attach("?")),
        (["exclamation", "point"], .attach("!")),
        (["exclamation", "mark"], .attach("!")),
        (["full", "stop"], .attach(".")),
        (["period"], .attach(".")),
        (["comma"], .attach(",")),
        (["semi", "colon"], .attach(";")),
        (["semicolon"], .attach(";")),
        (["colon"], .attach(":")),
        (["new", "paragraph"], .lineBreak("\n\n")),
        (["new", "line"], .lineBreak("\n")),
        (["newline"], .lineBreak("\n")),
        (["open", "quote"], .open("\"")),
        (["open", "quotes"], .open("\"")),
        (["begin", "quote"], .open("\"")),
        (["close", "quote"], .close("\"")),
        (["close", "quotes"], .close("\"")),
        (["end", "quote"], .close("\"")),
        (["unquote"], .close("\"")),
        (["open", "paren"], .open("(")),
        (["open", "parenthesis"], .open("(")),
        (["close", "paren"], .close(")")),
        (["close", "parenthesis"], .close(")"))
    ]

    private static let determiners: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those", "each", "every", "any", "some", "no", "another", "same", "whole",
        "entire", "per", "my", "your", "his", "her", "its", "our", "their", "whose", "one", "first", "second", "third", "last",
        "next", "previous", "final", "extra", "missing", "blank", "empty", "double", "big", "small"
    ]

    private static let nounModifiers: Set<String> = [
        "which", "what", "oxford", "serial", "trial", "grace", "waiting", "cooling", "notice", "billing", "reporting",
        "payment", "holding", "transition", "probation", "probationary", "study", "rest", "free", "time", "long", "short",
        "brief", "extended", "limited", "initial", "given", "certain", "specific", "fixed", "set", "early", "late", "class",
        "lunch", "incubation", "vesting", "lockup", "review", "quiet", "blackout"
    ]

    private static let literalFollowers: Set<String> = [
        "of", "key", "keys", "sign", "symbol", "symbols", "character", "characters", "separated", "delimited", "splice",
        "splices", "cancer", "button", "is", "was", "were", "will", "would", "has", "had", "ends", "ended", "began", "begins",
        "starts", "started", "lasts", "lasted", "during", "when", "where", "which", "for"
    ]

    private static func command(at index: Int, in pieces: [Piece]) -> (length: Int, mark: Mark)? {
        let first = pieces[index].word
        for (words, mark) in commands where words[0] == first && index + words.count <= pieces.count {
            let range = index..<(index + words.count)
            guard zip(range, words).allSatisfy({ pieces[$0].word == $1 }),
                  range.dropLast().allSatisfy({ pieces.connects($0) }) else { continue }
            let last = range.upperBound - 1
            if index > 0, pieces.connects(index - 1) {
                let previous = pieces[index - 1]
                if determiners.contains(previous.word) || (words.count == 1 && nounModifiers.contains(previous.word)) { return nil }
                if words == ["period"], previous.core.first?.isUppercase == true, previous.core != "I", !pieces.startsSentence(index - 1) { return nil }
            }
            if pieces.connects(last), literalFollowers.contains(pieces[last + 1].word) { return nil }
            switch mark {
            case .attach, .close: guard index > 0 else { return nil }
            case .open: guard last + 1 < pieces.count else { return nil }
            case .lineBreak: break
            }
            return (words.count, mark)
        }
        return nil
    }

    private static func applyCommands(_ pieces: inout [Piece]) {
        var index = 0
        while index < pieces.count {
            guard let (length, mark) = command(at: index, in: pieces) else { index += 1; continue }
            let removed = Array(pieces[index..<(index + length)])
            pieces.removeSubrange(index..<(index + length))
            let hasNext = index < pieces.count
            if hasNext { pieces[index].gap = Piece.widest(removed[0].gap, pieces[index].gap) }
            switch mark {
            case .attach(let symbol):
                pieces[index - 1].trail = Piece.stripping(pieces[index - 1].trail, ".,;:!?…") + symbol
                if ".?!".contains(symbol), hasNext { pieces[index].capitalize() }
            case .lineBreak(let separator):
                if hasNext {
                    pieces[index].gap = separator
                    pieces[index].capitalize()
                }
            case .open(let symbol):
                pieces[index].lead = symbol + pieces[index].lead
            case .close(let symbol):
                pieces[index - 1].trail += symbol + removed[removed.count - 1].trail
            }
        }
    }

    private static let fillers: Set<String> = ["um", "umm", "ummm", "uh", "uhh", "uhhh", "uhm", "erm", "er"]
    private static let stutters: Set<String> = [
        "i", "the", "a", "an", "to", "and", "of", "in", "on", "at", "for", "with", "we", "it", "my", "our", "your", "their",
        "this", "if", "but", "i'm", "it's", "we're", "i'll", "we'll"
    ]

    private static func removeDisfluencies(_ pieces: inout [Piece]) {
        var index = 0
        while index < pieces.count {
            let piece = pieces[index]
            let filler = fillers.contains(piece.word) && piece.core != "ER"
            let stutter = !filler && stutters.contains(piece.word) && index + 1 < pieces.count && pieces[index + 1].word == piece.word
                && (piece.trail.isEmpty || piece.trail == ",") && pieces[index + 1].lead.isEmpty && pieces[index + 1].gap == " "
            guard filler || stutter else { index += 1; continue }
            let opensSentence = pieces.startsSentence(index)
            pieces.remove(at: index)
            let ending = piece.trail.last { ".?!".contains($0) }
            if filler, index > 0, index == pieces.count || ending != nil, !pieces[index - 1].endsSentence {
                pieces[index - 1].trail = Piece.stripping(pieces[index - 1].trail, ",;:") + (ending.map { String($0) } ?? "")
            } else if filler, index > 0, piece.trail == ",", pieces[index - 1].trail == ",", !pieces.startsSentence(index - 1) {
                pieces[index - 1].trail = ""
            }
            guard index < pieces.count else { continue }
            pieces[index].gap = Piece.widest(piece.gap, pieces[index].gap)
            pieces[index].lead = piece.lead + pieces[index].lead
            if opensSentence { pieces[index].capitalize() }
        }
    }

    private static let domains: Set<String> = [
        "com", "org", "net", "io", "ai", "dev", "app", "co", "edu", "gov", "me", "us", "uk", "ca", "de", "fr", "xyz", "so",
        "sh", "tv", "info", "biz", "gg", "ly", "cc", "in", "jp", "au"
    ]

    private static let notMailboxes: Set<String> = [
        "me", "you", "us", "him", "her", "them", "it", "is", "are", "was", "were", "be", "am", "work", "works", "worked",
        "working", "look", "looking", "go", "went", "visit", "find", "found", "available", "online", "here", "there", "live",
        "located", "hosted", "based", "check", "up", "in", "out", "email", "emailed", "message", "reach", "contact", "write",
        "this", "that", "site", "website", "page", "store", "shop", "buy", "bought", "order", "ordered", "job", "jobs",
        "hired", "interview", "offer", "started", "join", "joined", "team", "anyone", "someone", "everyone", "people"
    ]

    private static func joinAddresses(_ pieces: inout [Piece]) {
        func label(_ index: Int) -> Bool {
            let core = pieces[index].core
            return pieces[index].isWord && core.first != "@" && core.last != "@" && core.filter({ $0 == "@" }).count <= 1
                && core.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "@" }
        }
        func linked(_ index: Int, by word: String) -> Bool {
            index >= 2 && pieces[index - 1].word == word && label(index - 2) && pieces.connects(index - 2) && pieces.connects(index - 1)
        }
        func spelled(_ range: ClosedRange<Int>) -> String {
            pieces[range].map { $0.word == "dot" ? "." : $0.word }.joined()
        }
        var index = 1
        while index + 1 < pieces.count {
            guard pieces[index].word == "dot", domains.contains(pieces[index + 1].word), label(index - 1),
                  pieces.connects(index - 1), pieces.connects(index) else { index += 1; continue }
            var start = index - 1, end = index + 1
            while linked(start, by: "dot") { start -= 2 }
            while end + 2 < pieces.count, pieces[end + 1].word == "dot", label(end + 2), pieces.connects(end), pieces.connects(end + 1) { end += 2 }
            var address = spelled(start...end)
            if !address.contains("@"), linked(start, by: "at"), !notMailboxes.contains(pieces[start - 2].word) {
                var mailbox = start - 2
                while linked(mailbox, by: "dot"), !notMailboxes.contains(pieces[mailbox - 2].word) { mailbox -= 2 }
                address = spelled(mailbox...(start - 2)) + "@" + address
                start = mailbox
            }
            pieces.replace(start...end, with: address)
            index = start + 1
        }
        index = 0
        while index + 1 < pieces.count {
            let mailbox = pieces[index].core, domain = pieces[index + 1].core
            if mailbox.count > 1, mailbox.last == "@", !mailbox.dropLast().contains("@"), pieces.connects(index),
               domain.wholeMatch(of: #/[\p{L}\p{N}_-]+(\.[\p{L}\p{N}_-]+)*\.[\p{L}]{2,}/#) != nil {
                pieces.replace(index...(index + 1), with: mailbox + domain)
            }
            index += 1
        }
    }
}

struct Piece {
    var gap: String
    var lead: String
    var core: String { didSet { word = Self.normalized(core) } }
    var trail: String
    private(set) var word: String

    private static let opening: Set<Character> = ["(", "[", "{", "\"", "“", "‘", "'", "¿", "¡"]
    private static let closing: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "]", "}", "\"", "”", "’", "'", "…"]

    init(gap: String, lead: String, core: String, trail: String) {
        self.gap = gap
        self.lead = lead
        self.core = core
        self.trail = trail
        word = Self.normalized(core)
    }

    private static func normalized(_ core: String) -> String {
        let lowered = core.lowercased()
        return lowered.contains("’") ? lowered.replacingOccurrences(of: "’", with: "'") : lowered
    }

    var isWord: Bool { core.contains { $0.isLetter || $0.isNumber } }
    var endsSentence: Bool {
        trail.last { !"\"”’')]}".contains($0) }.map { ".?!".contains($0) } ?? false
    }

    mutating func capitalize() {
        guard let first = core.first, first.isLowercase else { return }
        core = first.uppercased() + core.dropFirst()
    }

    static func split(_ text: String) -> [Piece] {
        var pieces: [Piece] = []
        var gap = "", chunk = ""
        for character in text + " " {
            if character.isWhitespace {
                if !chunk.isEmpty {
                    pieces.append(Piece(gap: gap, chunk: chunk))
                    chunk = ""
                    gap = ""
                }
                gap.append(character)
            } else {
                chunk.append(character)
            }
        }
        return pieces
    }

    static func join(_ pieces: [Piece]) -> String {
        pieces.reduce(into: "") { result, piece in
            let text = piece.lead + piece.core + piece.trail
            guard !text.isEmpty else { return }
            result += (result.isEmpty ? "" : piece.gap) + text
        }
    }

    static func widest(_ first: String, _ second: String) -> String {
        first.filter(\.isNewline).count > second.filter(\.isNewline).count ? first : second
    }

    static func stripping(_ text: String, _ characters: String) -> String {
        var text = text
        while let last = text.last, characters.contains(last) { text.removeLast() }
        return text
    }
}

extension Piece {
    init(gap: String, chunk: String) {
        let breaks = gap.filter(\.isNewline).count
        var lead = "", trail = "", core = Substring(chunk)
        while core.count > 1, let first = core.first, Self.opening.contains(first) {
            lead.append(first)
            core.removeFirst()
        }
        while core.count > 1, let last = core.last, Self.closing.contains(last) {
            trail.insert(last, at: trail.startIndex)
            core.removeLast()
        }
        self.init(gap: breaks > 1 ? "\n\n" : breaks == 1 ? "\n" : " ", lead: lead, core: String(core), trail: trail)
    }
}

extension Array where Element == Piece {
    func word(_ index: Int) -> String { indices.contains(index) ? self[index].word : "" }

    func connects(_ index: Int) -> Bool {
        index >= 0 && index + 1 < count && self[index].trail.isEmpty && self[index + 1].lead.isEmpty && self[index + 1].gap == " "
    }

    func startsSentence(_ index: Int) -> Bool {
        index == 0 || self[index - 1].endsSentence || self[index].gap.contains("\n")
    }

    mutating func replace(_ range: ClosedRange<Int>, with core: String) {
        let first = self[range.lowerBound], last = self[range.upperBound]
        replaceSubrange(range, with: [Piece(gap: first.gap, lead: first.lead, core: core, trail: last.trail)])
    }
}
