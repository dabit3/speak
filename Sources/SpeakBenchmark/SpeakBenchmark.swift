import CryptoKit
import Foundation
import SpeakCore

struct Sample: Codable {
    let spoken: String
    let expected: String
}

let corpus: [Sample] = [
    .init(spoken: "Can you review the pull request before we merge it into main?", expected: "Can you review the pull request before we merge it into main?"),
    .init(spoken: "I pushed a fix for the WebSocket reconnect bug, so the tests should pass now.", expected: "I pushed a fix for the WebSocket reconnect bug, so the tests should pass now."),
    .init(spoken: "Let's schedule the demo for Thursday at three thirty PM and invite the whole team.", expected: "Let's schedule the demo for Thursday at 3:30 PM and invite the whole team."),
    .init(spoken: "We migrated the database from MySQL to PostgreSQL last week, and it's been much faster since then.", expected: "We migrated the database from MySQL to PostgreSQL last week, and it's been much faster since then."),
    .init(spoken: "Hey Sarah, thanks for the feedback. I'll update the docs and send you a link tomorrow.", expected: "Hey Sarah, thanks for the feedback. I'll update the docs and send you a link tomorrow."),
    .init(spoken: "The deploy to Vercel failed because the environment variable wasn't set.", expected: "The deploy to Vercel failed because the environment variable wasn't set."),
    .init(spoken: "Um, so I think we should, uh, ship it on Friday.", expected: "So I think we should ship it on Friday."),
    .init(spoken: "Send the invoice to John, I mean Sarah.", expected: "Send the invoice to Sarah."),
    .init(spoken: "hey Sam comma can you check the logs question mark", expected: "Hey Sam, can you check the logs?"),
    .init(spoken: "We have twenty five users and the trial period ends in two weeks.", expected: "We have 25 users and the trial period ends in 2 weeks."),
    .init(spoken: "My email is nader at example dot com, so reach out anytime.", expected: "My email is nader@example.com, so reach out anytime."),
    .init(spoken: "Supabase handles authentication, storage, and the Postgres database for this project.", expected: "Supabase handles authentication, storage, and the Postgres database for this project."),
    .init(spoken: "Kubernetes keeps restarting the pod, and I'm not sure why. Could it be a memory leak?", expected: "Kubernetes keeps restarting the pod, and I'm not sure why. Could it be a memory leak?"),
    .init(spoken: "Please add Tailwind and GraphQL to the project, then restart the dev server.", expected: "Please add Tailwind and GraphQL to the project, then restart the dev server."),
    .init(spoken: "The budget is one hundred and fifty thousand dollars, which is about twelve percent more than last year.", expected: "The budget is $150,000, which is about 12% more than last year."),
    .init(spoken: "I'm going to be about ten minutes late. Go ahead and start without me.", expected: "I'm going to be about 10 minutes late. Go ahead and start without me."),
    .init(spoken: "Honestly, I don't think the new design is ready. Let's wait for the next sprint.", expected: "Honestly, I don't think the new design is ready. Let's wait for the next sprint."),
    .init(spoken: "Let's meet at three, no wait, four thirty PM on Tuesday.", expected: "Let's meet at 4:30 PM on Tuesday."),
    .init(spoken: "The OAuth callback returns a four oh one error when the token expires.", expected: "The OAuth callback returns a 401 error when the token expires."),
    .init(spoken: "Nader wrote a blog post about building AI agents with Devin and Claude.", expected: "Nader wrote a blog post about building AI agents with Devin and Claude."),
    .init(spoken: "Thanks for joining the call today. To recap, we agreed to launch the beta on October fifteenth, focus on onboarding, and revisit pricing after we hear from the first fifty customers.", expected: "Thanks for joining the call today. To recap, we agreed to launch the beta on October 15, focus on onboarding, and revisit pricing after we hear from the first 50 customers."),
    .init(spoken: "Where did you put the API keys? I can't find them in the dashboard.", expected: "Where did you put the API keys? I can't find them in the dashboard."),
    .init(spoken: "Their team said they're going to fix it over there by next week.", expected: "Their team said they're going to fix it over there by next week."),
    .init(spoken: "It's fine if the cache loses its data, but we should log a warning.", expected: "It's fine if the cache loses its data, but we should log a warning.")
]

let benchmarkVocabulary = "Supabase, PostgreSQL, MySQL, Vercel, Kubernetes, Tailwind, GraphQL, OAuth, WebSocket, Nader, Devin"
let previousPrompt = "One person dictating text to type into a Mac app, such as a message, email, document, note, or code editor. Speech can include names, technical terms, numbers, dates, times, prices, email addresses, and spoken punctuation such as comma, period, question mark, or new line."

struct Voice {
    let name: String
    let snr: Double?
    var label: String { snr.map { "\(name)+noise\(Int($0))dB" } ?? name }

    init(_ spec: String) {
        let parts = spec.split(separator: ":")
        name = String(parts[0])
        snr = parts.count > 1 ? Double(parts[1]) : nil
    }
}

struct Variant {
    var name: String
    var delay: TranscriptionDelay = .low
    var prompt: String? = TranscriptionConfiguration.prompt
    var vocabulary = ""
    var padding = 0
    var warm = true

    init(_ spec: String) throws {
        name = spec
        for token in spec.split(separator: "+").map(String.init) {
            if let delay = TranscriptionDelay(rawValue: token) { self.delay = delay; continue }
            switch token {
            case "baseline": break
            case "no-prompt": prompt = nil
            case "previous-prompt": prompt = previousPrompt
            case "keywords": vocabulary = benchmarkVocabulary
            case "cold": warm = false
            default:
                guard token.hasPrefix("pad"), let value = Int(token.dropFirst(3)) else {
                    throw DictationError("Unknown variant token: \(token)")
                }
                padding = value
            }
        }
    }

    var configuration: TranscriptionConfiguration { .init(language: "en", delay: delay, vocabulary: vocabulary) }
}

struct Clip {
    let index: Int
    let sample: Sample
    let voice: Voice
    let pcm: Data
    var seconds: Double { Double(pcm.count) / 48_000 }
}

struct ClipResult: Codable {
    var variant = ""
    var voice = ""
    var index = 0
    var spoken = ""
    var expected = ""
    var raw = ""
    var formatted = ""
    var pasted = ""
    var ideal = ""
    var error: String?
    var commitToFinal: Int?
    var commitToLastDelta: Int?
    var deltasAfterCommit: Int?
    var partialAtRelease: String?
    var lastPartial: String?
    var releaseToPaste: Int?
    var correctionLatency: Int?
    var correctionRequests = 0
    var correctionAccepted: Bool?
    var reusedPreview = false
    var asrErrors = 0
    var asrWords = 0
    var pastedWordErrors = 0
    var idealWordErrors = 0
    var formattedTokenErrors = 0
    var pastedTokenErrors = 0
    var idealTokenErrors = 0
    var expectedWords = 0
    var expectedTokens = 0
}

final class Timeline: @unchecked Sendable {
    private let lock = NSLock()
    private var marks: [String: ContinuousClock.Instant] = [:]
    func mark(_ name: String) { lock.withLock { if marks[name] == nil { marks[name] = .now } } }
    func update(_ name: String) { lock.withLock { marks[name] = .now } }
    private var counts: [String: Int] = [:]
    func count(_ name: String, after start: String) { lock.withLock { if marks[start] != nil { counts[name, default: 0] += 1 } } }
    func total(_ name: String) -> Int { lock.withLock { counts[name] ?? 0 } }
    func interval(from start: String, to end: String) -> Int? {
        lock.withLock {
            guard let a = marks[start], let b = marks[end] else { return nil }
            return milliseconds(a.duration(to: b))
        }
    }
}

func milliseconds(_ duration: Duration) -> Int {
    Int(duration.components.seconds * 1000) + Int(duration.components.attoseconds / 1_000_000_000_000_000)
}

final class BenchmarkSocket: TranscriptionSocket, @unchecked Sendable {
    private let inner: OpenAIWebSocket
    private let variant: Variant
    let timeline: Timeline

    init(apiKey: String, variant: Variant, timeline: Timeline) {
        inner = OpenAIWebSocket(apiKey: apiKey)
        self.variant = variant
        self.timeline = timeline
    }

    func send(_ text: String) async throws {
        var text = text
        if text.contains("\"session.update\"") { text = try rewrite(text) }
        if text.contains("input_audio_buffer.commit") { timeline.mark("commit") }
        try await inner.send(text)
    }

    func receive() async throws -> Data {
        let data = try await inner.receive()
        if data.range(of: Data("input_audio_transcription.completed".utf8)) != nil { timeline.mark("final") }
        if data.range(of: Data("input_audio_transcription.delta".utf8)) != nil {
            timeline.update("delta")
            timeline.count("delta", after: "commit")
        }
        return data
    }

    func close() { inner.close() }

    private func rewrite(_ text: String) throws -> String {
        guard var root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              var session = root["session"] as? [String: Any], var audio = session["audio"] as? [String: Any],
              var input = audio["input"] as? [String: Any], var transcription = input["transcription"] as? [String: Any] else { return text }
        transcription["prompt"] = variant.prompt
        input["transcription"] = transcription
        audio["input"] = input
        session["audio"] = audio
        root["session"] = session
        return String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    }
}

final class RecordingCorrector: TranscriptCorrecting, @unchecked Sendable {
    struct Outcome {
        let output: String?
        let milliseconds: Int
    }

    private let base: any TranscriptCorrecting
    private let lock = NSLock()
    private var tasks: [String: Task<Outcome, Never>] = [:]
    private(set) var requests = 0

    init(base: any TranscriptCorrecting) { self.base = base }

    func correct(_ text: String, context: CorrectionContext) async throws -> String {
        let base = self.base
        let task = Task<Outcome, Never> {
            let start = ContinuousClock.now
            let output = try? await base.correct(text, context: context)
            return Outcome(output: output, milliseconds: milliseconds(start.duration(to: .now)))
        }
        lock.withLock {
            tasks[text] = task
            requests += 1
        }
        guard let output = await task.value.output else { throw DictationError("Correction failed.") }
        return output
    }

    func outcome(for text: String) async -> Outcome? {
        let task = lock.withLock { tasks[text] }
        return await task?.value
    }

    var requestCount: Int { lock.withLock { requests } }
}

final class PacedAudio: @unchecked Sendable {
    private let pcm: Data
    private let padding: Data
    private let onRelease: @Sendable () async -> Void
    private var offset = 0
    private var start: ContinuousClock.Instant?
    private var released = false
    private let chunk = 960

    init(pcm: Data, paddingMilliseconds: Int, onRelease: @escaping @Sendable () async -> Void) {
        self.pcm = pcm
        padding = Data(count: paddingMilliseconds * 48)
        self.onRelease = onRelease
    }

    func next() async throws -> Data? {
        let clock = ContinuousClock()
        let start = self.start ?? clock.now
        self.start = start
        if offset < pcm.count {
            let index = offset / chunk
            try await clock.sleep(until: start + .milliseconds(20 * (index + 1)))
            let data = pcm.subdata(in: offset..<min(offset + chunk, pcm.count))
            offset += chunk
            return data
        }
        guard !released else { return nil }
        released = true
        await onRelease()
        return padding.isEmpty ? nil : padding
    }

    var stream: AsyncThrowingStream<Data, Error> { AsyncThrowingStream { try await self.next() } }
}

enum Metrics {
    static func words(_ text: String) -> [String] {
        let joined = text.lowercased().replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"(?<=\d),(?=\d)"#, with: "", options: .regularExpression)
        let cleaned = String(joined.map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " })
        return cleaned.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }.filter { !$0.isEmpty }
    }

    static func tokens(_ text: String) -> [String] {
        text.replacingOccurrences(of: "’", with: "'").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func distance(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
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

    static func percentile(_ values: [Int], _ p: Double) -> String {
        guard !values.isEmpty else { return "-" }
        let sorted = values.sorted()
        return String(sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))])
    }

    static func rate(_ errors: Int, _ total: Int) -> String {
        total == 0 ? "-" : String(format: "%.1f%%", Double(errors) * 100 / Double(total))
    }
}

enum AudioLibrary {
    static let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/benchmark/audio")

    static func load(_ sample: Sample, voice: Voice, index: Int) throws -> Data {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data("\(voice.name)|\(sample.spoken)".utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent("\(voice.name)-\(digest).wav")
        if !FileManager.default.fileExists(atPath: file.path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-v", voice.name, "--file-format=WAVE", "--data-format=LEI16@24000", "-o", file.path, sample.spoken]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw DictationError("say failed for voice \(voice.name)") }
        }
        var pcm = try pcmData(from: Data(contentsOf: file))
        pcm = Data(count: 150 * 48) + pcm
        if let snr = voice.snr { pcm = addNoise(to: pcm, snr: snr, seed: UInt64(index + 1)) }
        return pcm
    }

    private static func pcmData(from wav: Data) throws -> Data {
        var offset = 12
        while offset + 8 <= wav.count {
            let id = String(decoding: wav[offset..<offset + 4], as: UTF8.self)
            let size = wav[offset + 4..<offset + 8].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            if id == "data" { return wav.subdata(in: offset + 8..<min(wav.count, offset + 8 + size)) }
            offset += 8 + size + size % 2
        }
        throw DictationError("The WAV file has no audio data.")
    }

    private static func addNoise(to pcm: Data, snr: Double, seed: UInt64) -> Data {
        var samples = pcm.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        let voiced = samples.map { Double($0) }.filter { abs($0) > 300 }
        let speech = sqrt(voiced.reduce(0) { $0 + $1 * $1 } / Double(max(1, voiced.count)))
        let level = speech / pow(10, snr / 20)
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        func uniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Double(state >> 11) + 0.5) / Double(1 << 53)
        }
        var brown = 0.0
        for i in samples.indices {
            let white = sqrt(-2 * log(uniform())) * cos(2 * .pi * uniform())
            brown = 0.97 * brown + 0.03 * white * 4
            let noise = (0.6 * white + 0.4 * brown) * level
            samples[i] = Int16(clamping: Int((Double(samples[i]) + noise).rounded()))
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

@MainActor
final class PartialLog {
    var latest = ""
    var atRelease = ""
}

@MainActor
final class Runner {
    let apiKey: String
    let concurrency: Int

    init(apiKey: String, concurrency: Int) {
        self.apiKey = apiKey
        self.concurrency = concurrency
    }

    func run(_ variant: Variant, clips: [Clip]) async -> [ClipResult] {
        var results: [ClipResult] = []
        await withTaskGroup(of: ClipResult.self) { group in
            var pending = clips.makeIterator()
            for _ in 0..<concurrency {
                guard let clip = pending.next() else { break }
                group.addTask { await self.run(variant, clip: clip) }
            }
            for await result in group {
                results.append(result)
                FileHandle.standardError.write(Data(".".utf8))
                if let clip = pending.next() { group.addTask { await self.run(variant, clip: clip) } }
            }
        }
        FileHandle.standardError.write(Data("\n".utf8))
        return results.sorted { ($0.voice, $0.index) < ($1.voice, $1.index) }
    }

    private func run(_ variant: Variant, clip: Clip) async -> ClipResult {
        var result = ClipResult(variant: variant.name, voice: clip.voice.label, index: clip.index, spoken: clip.sample.spoken, expected: clip.sample.expected)
        let timeline = Timeline()
        let configuration = variant.configuration
        let transcriber = RealtimeTranscriber(socket: BenchmarkSocket(apiKey: apiKey, variant: variant, timeline: timeline))
        let session = variant.warm ? OpenAITranscriptCorrector.session : Self.session()
        defer { if !variant.warm { session.finishTasksAndInvalidate() } }
        let corrector = OpenAITranscriptCorrector(apiKey: apiKey, session: session)
        let recorder = RecordingCorrector(base: corrector)
        let correction = SmartCorrection(service: recorder, context: CorrectionContext(language: "en", keywords: configuration.keywords, application: "Notes"))
        if variant.warm { corrector.prepare() }
        let partials = PartialLog()
        let audio = PacedAudio(pcm: clip.pcm, paddingMilliseconds: variant.padding) { @Sendable in
            await MainActor.run {
                timeline.mark("release")
                partials.atRelease = partials.latest
                correction.prepareFinal()
                transcriber.finishSoon()
            }
        }
        do {
            let raw = try await transcriber.transcribe(audio: audio.stream, configuration: configuration, onReady: {}, onPartial: { text in
                let formatted = DictationFormatter.format(text, language: "en")
                partials.latest = formatted
                correction.preview(formatted)
            })
            result.raw = raw
            result.partialAtRelease = partials.atRelease
            result.lastPartial = partials.latest
            result.formatted = DictationFormatter.format(raw, language: "en")
            let requestsBeforeFinal = recorder.requestCount
            result.pasted = result.formatted.isEmpty ? "" : await correction.finish(result.formatted)
            timeline.mark("paste")
            result.reusedPreview = CorrectionPolicy.isEligible(result.formatted) && recorder.requestCount == requestsBeforeFinal
            result.correctionRequests = recorder.requestCount
            if let outcome = await recorder.outcome(for: result.formatted) {
                result.correctionLatency = outcome.milliseconds
                let accepted = outcome.output.flatMap { CorrectionPolicy.accept(result.formatted, candidate: $0, keywords: configuration.keywords) }
                result.correctionAccepted = accepted != nil
                result.ideal = accepted ?? result.formatted
            } else {
                result.ideal = result.formatted
            }
        } catch {
            result.error = error.localizedDescription
        }
        result.commitToFinal = timeline.interval(from: "commit", to: "final")
        result.commitToLastDelta = timeline.interval(from: "commit", to: "delta")
        result.deltasAfterCommit = timeline.total("delta")
        result.releaseToPaste = timeline.interval(from: "release", to: "paste")
        score(&result)
        return result
    }

    private func score(_ result: inout ClipResult) {
        let reference = Metrics.words(DictationFormatter.format(result.spoken, language: "en"))
        let expectedWords = Metrics.words(result.expected), expectedTokens = Metrics.tokens(result.expected)
        result.asrWords = reference.count
        result.expectedWords = expectedWords.count
        result.expectedTokens = expectedTokens.count
        result.asrErrors = Metrics.distance(Metrics.words(result.formatted), reference)
        result.pastedWordErrors = Metrics.distance(Metrics.words(result.pasted), expectedWords)
        result.idealWordErrors = Metrics.distance(Metrics.words(result.ideal), expectedWords)
        result.formattedTokenErrors = Metrics.distance(Metrics.tokens(result.formatted), expectedTokens)
        result.pastedTokenErrors = Metrics.distance(Metrics.tokens(result.pasted), expectedTokens)
        result.idealTokenErrors = Metrics.distance(Metrics.tokens(result.ideal), expectedTokens)
    }

    nonisolated static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        return URLSession(configuration: configuration)
    }
}

func summarize(_ variant: String, _ results: [ClipResult]) -> String {
    let ok = results.filter { $0.error == nil }
    func sum(_ key: KeyPath<ClipResult, Int>) -> Int { ok.reduce(0) { $0 + $1[keyPath: key] } }
    let changed = ok.filter { $0.ideal != $0.formatted }
    let applied = changed.filter { $0.pasted == $0.ideal }
    let columns = [
        variant,
        "\(ok.count)/\(results.count)",
        Metrics.rate(sum(\.asrErrors), sum(\.asrWords)),
        Metrics.rate(sum(\.pastedWordErrors), sum(\.expectedWords)),
        Metrics.rate(sum(\.idealWordErrors), sum(\.expectedWords)),
        Metrics.rate(sum(\.formattedTokenErrors), sum(\.expectedTokens)),
        Metrics.rate(sum(\.pastedTokenErrors), sum(\.expectedTokens)),
        Metrics.rate(sum(\.idealTokenErrors), sum(\.expectedTokens)),
        "\(ok.filter { $0.pasted == $0.expected }.count)",
        "\(Metrics.percentile(ok.compactMap(\.commitToFinal), 0.5))/\(Metrics.percentile(ok.compactMap(\.commitToFinal), 0.9))",
        "\(Metrics.percentile(ok.compactMap(\.releaseToPaste), 0.5))/\(Metrics.percentile(ok.compactMap(\.releaseToPaste), 0.9))",
        "\(Metrics.percentile(ok.compactMap(\.correctionLatency), 0.5))/\(Metrics.percentile(ok.compactMap(\.correctionLatency), 0.9))",
        "\(applied.count)/\(changed.count)",
        "\(ok.filter { $0.correctionAccepted == false }.count)",
        "\(ok.filter(\.reusedPreview).count)"
    ]
    return columns.joined(separator: " | ")
}

let header = "variant | ok | ASR WER | pasted WER | ideal WER | formatted TER | pasted TER | ideal TER | exact | commit→final p50/p90 ms | release→paste p50/p90 ms | correction p50/p90 ms | in time | rejected | reused"

func correctionLatency(apiKey: String, texts: [String], modes: [String]) async {
    print("mode | requests | p50 ms | p90 ms | max ms")
    for mode in modes {
        var values: [Int] = [], failures = 0
        for text in texts {
            let session = mode == "cold" ? Runner.session() : OpenAITranscriptCorrector.session
            let corrector = OpenAITranscriptCorrector(apiKey: apiKey, session: session)
            if mode != "cold" {
                corrector.prepare()
                try? await Task.sleep(for: .seconds(1))
            }
            let start = ContinuousClock.now
            do {
                _ = try await corrector.correct(text, context: CorrectionContext(language: "en", keywords: [], application: "Notes"))
                values.append(milliseconds(start.duration(to: .now)))
            } catch { failures += 1 }
            if mode == "cold" { session.finishTasksAndInvalidate() }
        }
        print("\(mode) | \(values.count) ok, \(failures) failed | \(Metrics.percentile(values, 0.5)) | \(Metrics.percentile(values, 0.9)) | \(values.max() ?? 0)")
    }
}

func replay(apiKey: String, file: URL, vocabulary: String) async throws {
    let results = try JSONDecoder().decode([ClipResult].self, from: Data(contentsOf: file))
    let keywords = TranscriptionConfiguration(language: "en", delay: .low, vocabulary: vocabulary).keywords
    let corrector = OpenAITranscriptCorrector(apiKey: apiKey)
    corrector.prepare()
    var latencies: [Int] = [], before = 0, after = 0, tokens = 0, rejected = 0, failed = 0
    for result in results where result.error == nil {
        let start = ContinuousClock.now
        let candidate = try? await corrector.correct(result.formatted, context: CorrectionContext(language: "en", keywords: keywords, application: "Notes"))
        latencies.append(milliseconds(start.duration(to: .now)))
        let accepted = candidate.flatMap { CorrectionPolicy.accept(result.formatted, candidate: $0, keywords: keywords) }
        let expected = Metrics.tokens(result.expected)
        tokens += expected.count
        before += Metrics.distance(Metrics.tokens(result.formatted), expected)
        after += Metrics.distance(Metrics.tokens(accepted ?? result.formatted), expected)
        if candidate == nil { failed += 1 }
        if let candidate, accepted == nil {
            rejected += 1
            print("REJECTED \(result.voice) #\(result.index)\n  input:     \(result.formatted)\n  candidate: \(candidate)\n  expected:  \(result.expected)")
        } else if let accepted, accepted != result.expected {
            print("MISMATCH \(result.voice) #\(result.index)\n  input:     \(result.formatted)\n  accepted:  \(accepted)\n  expected:  \(result.expected)")
        }
    }
    print("replayed \(latencies.count), failed \(failed), rejected \(rejected), TER \(Metrics.rate(before, tokens)) -> \(Metrics.rate(after, tokens)), latency p50/p90 \(Metrics.percentile(latencies, 0.5))/\(Metrics.percentile(latencies, 0.9)) ms")
}

@main
struct SpeakBenchmark {
    static func main() async {
        do { try await run() } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(2)
        }
    }

    @MainActor static func run() async throws {
        var options: [String: String] = [:]
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            guard argument.hasPrefix("--") else { throw DictationError("Unexpected argument: \(argument)") }
            let name = String(argument.dropFirst(2))
            options[name] = ["dry-run", "help"].contains(name) ? "" : arguments.next() ?? ""
        }
        if options["help"] != nil {
            print("""
            Usage: swift run -c release SpeakBenchmark [--variants low,medium,high+keywords] [--voices Samantha,Daniel:15]
                   [--limit N] [--concurrency N] [--dry-run] [--correction-latency cold,warm]
                   [--replay .build/benchmark/results/<file>.json] [--vocabulary "Nader, Vercel"]
            Variant tokens: minimal low medium high xhigh baseline no-prompt previous-prompt keywords padN cold
            Reads the API key from OPENAI_API_KEY. Audio is generated with macOS text-to-speech.
            """)
            return
        }
        let voices = (options["voices"] ?? "Samantha,Daniel:15").split(separator: ",").map { Voice(String($0)) }
        let samples = Array(corpus.prefix(Int(options["limit"] ?? "") ?? corpus.count))
        let variants = try (options["variants"] ?? "baseline").split(separator: ",").map { try Variant(String($0)) }
        var clips: [Clip] = []
        for voice in voices {
            for (index, sample) in samples.enumerated() {
                clips.append(Clip(index: index, sample: sample, voice: voice, pcm: try AudioLibrary.load(sample, voice: voice, index: index)))
            }
        }
        let minutes = clips.reduce(0) { $0 + $1.seconds } / 60
        print(String(format: "%d clips, %.1f audio minutes per variant, %d variants, about $%.2f of transcription", clips.count, minutes, variants.count, minutes * Double(variants.count) * 0.017))
        if options["dry-run"] != nil { return }
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            throw DictationError("Set OPENAI_API_KEY to run the benchmark.")
        }
        if let file = options["replay"] {
            try await replay(apiKey: apiKey, file: URL(fileURLWithPath: file), vocabulary: options["vocabulary"] ?? "")
            return
        }
        if let modes = options["correction-latency"] {
            await correctionLatency(apiKey: apiKey, texts: samples.map { DictationFormatter.format($0.spoken, language: "en") }, modes: modes.split(separator: ",").map(String.init))
            return
        }
        let runner = Runner(apiKey: apiKey, concurrency: Int(options["concurrency"] ?? "") ?? 8)
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/benchmark/results")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        var lines: [String] = []
        for variant in variants {
            FileHandle.standardError.write(Data("\(variant.name) ".utf8))
            let results = await runner.run(variant, clips: clips)
            let file = output.appendingPathComponent("\(stamp)-\(variant.name).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: file)
            lines.append(summarize(variant.name, results))
            for failure in results where failure.error != nil { print("  \(failure.voice) #\(failure.index): \(failure.error!)") }
        }
        print(header)
        lines.forEach { print($0) }
        print("Details: \(output.path)/\(stamp)-*.json")
    }
}
