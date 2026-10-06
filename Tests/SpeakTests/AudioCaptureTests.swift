import CoreAudio
import XCTest
import SpeakCore
@testable import Speak

final class AudioCaptureTests: XCTestCase {
    private let bufferBytes = 2400 * MemoryLayout<Int16>.size
    private let voice = (0..<2400).map { 0.07 * sin(2 * Float.pi * 220 * Float($0) / 24_000) }
    private let quiet = (0..<2400).map { Float(($0 * 7919) % 101 - 50) / 50 * 0.0003 }
    private let silence = [Float](repeating: 0, count: 2400)

    func testKeepsListeningAfterReleaseUntilSpeechStops() async throws {
        let capture = AudioCapture(microphone: nil)
        capture.receive([quiet], at: 0.1)
        for step in 2...10 { capture.receive([voice], at: Double(step) / 10) }
        capture.finish(at: 1.0)
        capture.receive([voice], at: 1.1)
        capture.receive([quiet], at: 1.2)
        capture.receive([voice], at: 1.3)
        let audio = try await collect(capture.stream)
        XCTAssertEqual(audio.count, 12 * bufferBytes)
    }

    func testStopsRightAwayWhenTheSpeakerHadAlreadyFinished() async throws {
        let capture = AudioCapture(microphone: nil)
        capture.receive([quiet], at: 0.1)
        for step in 2...8 { capture.receive([voice], at: Double(step) / 10) }
        capture.receive([quiet], at: 0.9)
        capture.finish(at: 0.95)
        capture.receive([quiet], at: 1.0)
        capture.receive([quiet], at: 1.1)
        let audio = try await collect(capture.stream)
        XCTAssertEqual(audio.count, 10 * bufferBytes)
    }

    func testShortQuietBuffersDoNotCutOffTheNextSpeechBuffer() async throws {
        let capture = AudioCapture(microphone: nil)
        capture.receive([quiet], at: 0.1)
        capture.receive([voice], at: 0.2)
        capture.finish(at: 0.2)
        for step in 1...8 {
            capture.receive([Array(quiet.prefix(120))], at: 0.2 + Double(step) * 0.005)
        }
        capture.receive([voice], at: 0.34)
        capture.receive([quiet], at: 0.44)
        let audio = try await collect(capture.stream)
        XCTAssertEqual(audio.count, 4 * bufferBytes + 8 * 120 * MemoryLayout<Int16>.size)
    }

    func testStopsAtTheTailLimitWhenSoundContinues() async throws {
        let capture = AudioCapture(microphone: nil)
        capture.receive([quiet], at: 0.1)
        for step in 2...10 { capture.receive([voice], at: Double(step) / 10) }
        capture.finish(at: 0.99)
        for step in 11...15 { capture.receive([voice], at: Double(step) / 10) }
        let audio = try await collect(capture.stream)
        XCTAssertEqual(audio.count, 13 * bufferBytes)
        XCTAssertEqual(AudioCapture.maximumTail, 0.3)
    }

    func testSilentMicrophoneEndsWithAnErrorThatNamesIt() async {
        let capture = AudioCapture(microphone: Microphone(name: "ZoomAudioDevice", transport: kAudioDeviceTransportTypeVirtual, source: nil))
        for step in 1...6 { capture.receive([silence], at: Double(step) / 10) }
        capture.finish(at: 0.6)
        capture.receive([silence], at: 0.7)
        do {
            _ = try await collect(capture.stream)
            XCTFail("A silent microphone must not reach the transcriber as a normal recording")
        } catch {
            let error = error as? DictationError
            XCTAssertEqual(error?.message, DictationError.silentMicrophone("ZoomAudioDevice").message)
            XCTAssertEqual(error?.dismissesAutomatically, false)
        }
    }

    func testShortSilentRecordingIsLeftToTheServer() async throws {
        let capture = AudioCapture(microphone: nil)
        capture.receive([silence], at: 0.1)
        capture.finish(at: 0.15)
        capture.receive([silence], at: 0.2)
        let audio = try await collect(capture.stream)
        XCTAssertEqual(audio.count, 2 * bufferBytes)
    }

    func testCancellingASilentRecordingEndsQuietly() async throws {
        let capture = AudioCapture(microphone: nil)
        for step in 1...6 { capture.receive([silence], at: Double(step) / 10) }
        capture.stop()
        capture.receive([voice], at: 0.7)
        let audio = try await collect(capture.stream)
        XCTAssertEqual(audio.count, 6 * bufferBytes)
    }

    func testDeviceChangeWhileRecordingIsAnError() async {
        let capture = AudioCapture(microphone: nil)
        capture.receive([voice], at: 0.1)
        capture.deviceChanged()
        do {
            _ = try await collect(capture.stream)
            XCTFail("A device change while recording must stop the take")
        } catch { XCTAssertTrue(error.localizedDescription.contains("microphone changed")) }
    }

    func testDeviceChangeDuringTheReleaseTailKeepsTheRecording() async throws {
        let capture = AudioCapture(microphone: nil)
        capture.receive([quiet], at: 0.1)
        capture.receive([voice], at: 0.2)
        capture.finish(at: 0.2)
        capture.deviceChanged()
        let audio = try await collect(capture.stream)
        XCTAssertEqual(audio.count, 2 * bufferBytes)
    }

    func testMicrophoneOnTheSecondInputIsSent() async throws {
        let capture = AudioCapture(microphone: nil)
        capture.receive([silence, voice], at: 0.1)
        capture.stop()
        let samples = try await collect(capture.stream).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        XCTAssertGreaterThan(samples.map { abs(Int($0)) }.max() ?? 0, Int(0.065 * Float(Int16.max)))
    }

    func testNoiseReductionMatchesTheMicrophone() {
        let cases: [(Microphone, NoiseReduction)] = [
            (Microphone(name: "MacBook Pro Microphone", transport: kAudioDeviceTransportTypeBuiltIn, source: "imic"), .farField),
            (Microphone(name: "MacBook Pro Microphone", transport: kAudioDeviceTransportTypeBuiltIn, source: nil), .farField),
            (Microphone(name: "External Microphone", transport: kAudioDeviceTransportTypeBuiltIn, source: "emic"), .nearField),
            (Microphone(name: "iPhone Microphone", transport: kAudioDeviceTransportTypeContinuityCaptureWired, source: nil), .farField),
            (Microphone(name: "iPhone Microphone", transport: kAudioDeviceTransportTypeContinuityCaptureWireless, source: nil), .farField),
            (Microphone(name: "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth, source: nil), .nearField),
            (Microphone(name: "USB Headset", transport: kAudioDeviceTransportTypeUSB, source: nil), .nearField),
            (Microphone(name: "Krisp Microphone", transport: kAudioDeviceTransportTypeVirtual, source: nil), .nearField)
        ]
        for (microphone, expected) in cases {
            XCTAssertEqual(microphone.noiseReduction, expected, microphone.name ?? "")
        }
        XCTAssertEqual(AudioCapture(microphone: nil).noiseReduction, .nearField)
    }

    func testReadsTheDefaultInputDevice() throws {
        guard let microphone = Microphone.current() else { throw XCTSkip("This Mac has no default input device.") }
        XCTAssertFalse(microphone.name?.isEmpty ?? true)
        XCTAssertNotEqual(microphone.transport, 0)
    }

    private func collect(_ stream: AsyncThrowingStream<Data, Error>) async throws -> Data {
        var result = Data()
        for try await chunk in stream { result += chunk }
        return result
    }
}
