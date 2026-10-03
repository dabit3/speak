import XCTest
@testable import SpeakCore

enum Signal {
    static let rate = 24_000

    static func tone(rms: Float, seconds: Double, frequency: Float = 220) -> [Float] {
        let amplitude = rms * Float(2).squareRoot()
        return (0..<count(seconds)).map { amplitude * sin(2 * .pi * frequency * Float($0) / Float(rate)) }
    }

    static func speech(peak rms: Float, seconds: Double) -> [Float] {
        tone(rms: rms, seconds: seconds).enumerated().map { $1 * abs(sin(2 * .pi * 4 * Float($0) / Float(rate))) }
    }

    static func noise(rms: Float, seconds: Double, seed: UInt64 = 1) -> [Float] {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        return (0..<count(seconds)).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Float(state >> 40) / Float(1 << 24) * 2 - 1) * rms * Float(3).squareRoot()
        }
    }

    static func silence(_ seconds: Double) -> [Float] { Array(repeating: 0, count: count(seconds)) }
    static func add(_ a: [Float], _ b: [Float]) -> [Float] { zip(a, b).map { $0 + $1 } }
    static func count(_ seconds: Double) -> Int { Int(seconds * Double(rate)) }

    static func decode(_ audio: Data) -> [Float] {
        audio.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map { Float($0) / Float(Int16.max) }
    }

    static func rms(_ samples: [Float]) -> Float { AudioConditioner.rms(samples[...]) }

    static func frameLevels(_ samples: [Float]) -> [Float] {
        stride(from: 0, to: samples.count, by: 240).map { AudioConditioner.rms(samples[$0..<min($0 + 240, samples.count)]) }
    }
}

final class AudioConditionerTests: XCTestCase {
    func testHearsAMicrophoneOnAnyInputChannel() {
        let voice = Signal.speech(peak: 0.2, seconds: 0.5)
        let empty = Signal.noise(rms: 0.0001, seconds: 0.5)
        for (layout, index) in [(2, 1), (4, 2)] {
            var conditioner = AudioConditioner()
            let channels = (0..<layout).map { $0 == index ? voice : empty }
            let output = Signal.decode(conditioner.process(channels).audio)
            XCTAssertEqual(output.count, voice.count)
            XCTAssertEqual(Signal.rms(output), Signal.rms(voice), accuracy: Signal.rms(voice) * 0.02, "\(layout) channels")
        }
    }

    func testFollowsAMicrophoneThatStartsAfterSilence() {
        var conditioner = AudioConditioner()
        let empty = Signal.noise(rms: 0.0001, seconds: 0.1)
        _ = conditioner.process([empty, Signal.noise(rms: 0.0001, seconds: 0.1, seed: 2)])
        let voice = Signal.speech(peak: 0.2, seconds: 0.1)
        let output = Signal.decode(conditioner.process([empty, voice]).audio)
        XCTAssertGreaterThan(Signal.rms(output), Signal.rms(voice) * 0.95)
    }

    func testIdenticalChannelsKeepTheirLevel() {
        var conditioner = AudioConditioner()
        let voice = Signal.speech(peak: 0.2, seconds: 0.5)
        let output = Signal.decode(conditioner.process([voice, voice]).audio)
        XCTAssertEqual(Signal.rms(output), Signal.rms(voice), accuracy: 0.001)
    }

    func testLeavesNormalSpeechUnchanged() {
        var conditioner = AudioConditioner()
        let input = Signal.noise(rms: 0.0003, seconds: 0.3) + Signal.add(Signal.speech(peak: 0.2, seconds: 1), Signal.noise(rms: 0.0003, seconds: 1, seed: 2))
        let output = Signal.decode(conditioner.process([input]).audio)
        XCTAssertEqual(conditioner.gain, 1)
        XCTAssertLessThanOrEqual(zip(input, output).map { abs($0 - $1) }.max() ?? 1, 1 / Float(Int16.max))
    }

    func testRaisesQuietSpeechTowardTheTarget() {
        var conditioner = AudioConditioner()
        let input = Signal.noise(rms: 0.0003, seconds: 0.3) + Signal.add(Signal.speech(peak: 0.03, seconds: 2), Signal.noise(rms: 0.0003, seconds: 2, seed: 2))
        let output = Signal.decode(conditioner.process([input]).audio)
        XCTAssertEqual(conditioner.gain, AudioConditioner.targetLevel / 0.03, accuracy: 0.6)
        let loudest = Signal.frameLevels(Array(output.suffix(Signal.count(0.5)))).max() ?? 0
        XCTAssertEqual(loudest, AudioConditioner.targetLevel, accuracy: 0.02)
    }

    func testLimitsTheBoostForVeryQuietSpeech() {
        var conditioner = AudioConditioner()
        let input = Signal.noise(rms: 0.0002, seconds: 0.3) + Signal.add(Signal.speech(peak: 0.005, seconds: 2), Signal.noise(rms: 0.0002, seconds: 2, seed: 2))
        _ = conditioner.process([input])
        XCTAssertEqual(conditioner.gain, AudioConditioner.maximumGain, accuracy: 0.01)
    }

    func testDoesNotRaiseSteadyBackgroundNoise() {
        var conditioner = AudioConditioner()
        let input = Signal.silence(0.05) + Signal.noise(rms: 0.004, seconds: 2)
        let output = Signal.decode(conditioner.process([input]).audio)
        XCTAssertEqual(conditioner.gain, 1)
        XCTAssertEqual(Signal.rms(output), Signal.rms(input), accuracy: 0.0002)
    }

    func testSuddenLoudSoundDoesNotClipAfterABoost() {
        var conditioner = AudioConditioner()
        let quiet = Signal.noise(rms: 0.0003, seconds: 0.3) + Signal.add(Signal.speech(peak: 0.01, seconds: 1), Signal.noise(rms: 0.0003, seconds: 1, seed: 2))
        _ = conditioner.process([quiet])
        XCTAssertEqual(conditioner.gain, AudioConditioner.maximumGain, accuracy: 0.01)
        let onset = Array(quiet.suffix(100)) + Signal.tone(rms: 0.6, seconds: 0.2)
        let output = Signal.decode(conditioner.process([onset]).audio)
        XCTAssertLessThan(output.map(abs).max() ?? 1, 0.9)
    }

    func testRecognizesAMicrophoneThatSendsOnlySilence() {
        var silent = AudioConditioner()
        _ = silent.process([Signal.silence(1)])
        XCTAssertFalse(silent.heardSound)
        XCTAssertEqual(silent.duration, 1, accuracy: 0.001)
        var dithered = AudioConditioner()
        _ = dithered.process([Signal.noise(rms: 0.5 / Float(Int16.max), seconds: 1)])
        XCTAssertFalse(dithered.heardSound)
        var quietRoom = AudioConditioner()
        _ = quietRoom.process([Signal.noise(rms: 0.0005, seconds: 1)])
        XCTAssertTrue(quietRoom.heardSound)
    }

    func testMeasuresQuietAfterSpeech() {
        var conditioner = AudioConditioner()
        _ = conditioner.process([Signal.noise(rms: 0.0003, seconds: 0.3) + Signal.tone(rms: 0.05, seconds: 0.5)])
        XCTAssertEqual(conditioner.trailingQuiet, 0)
        _ = conditioner.process([Signal.noise(rms: 0.0003, seconds: 0.2, seed: 2)])
        XCTAssertEqual(conditioner.trailingQuiet, 0.2, accuracy: 0.011)
        _ = conditioner.process([Signal.tone(rms: 0.05, seconds: 0.05)])
        XCTAssertEqual(conditioner.trailingQuiet, 0)
    }
}
