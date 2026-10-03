import AVFoundation
import CoreAudio
import SpeakCore

struct Microphone: Equatable {
    let name: String?
    let transport: UInt32
    let source: String?

    var noiseReduction: NoiseReduction {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return source == "emic" ? .nearField : .farField
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: return .farField
        default: return .nearField
        }
    }

    static func current() -> Microphone? {
        guard let device: AudioDeviceID = property(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, initial: 0),
              device != kAudioObjectUnknown else { return nil }
        let name: Unmanaged<CFString>?? = property(device, kAudioObjectPropertyName, initial: nil)
        let source: UInt32? = property(device, kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeInput, initial: 0)
        return Microphone(
            name: name??.takeRetainedValue() as String?,
            transport: property(device, kAudioDevicePropertyTransportType, initial: 0) ?? 0,
            source: source.map { code in String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, as: UTF8.self) }
        )
    }

    private static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? value : nil
    }
}

final class AudioCapture: @unchecked Sendable {
    static let maximumTail: TimeInterval = 0.3
    static let quietAfterSpeech: TimeInterval = 0.08
    static let minimumSilentDuration: TimeInterval = 0.4
    let microphone: Microphone?
    let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let lock = NSLock()
    private var conditioner = AudioConditioner()
    private var onLevel: (@Sendable (Float) -> Void)?
    private var release: (earliest: TimeInterval, latest: TimeInterval)?
    private var ended = false
    private var latency: TimeInterval = 0
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?

    init(microphone: Microphone? = Microphone.current()) {
        self.microphone = microphone
        (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(500))
    }

    var noiseReduction: NoiseReduction { microphone?.noiseReduction ?? .nearField }

    func start(onLevel: @escaping @Sendable (Float) -> Void) throws -> AsyncThrowingStream<Data, Error> {
        lock.withLock { self.onLevel = onLevel }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0,
              let target = Self.resampledFormat(for: source),
              let converter = AVAudioConverter(from: source, to: target) else {
            throw DictationError("No microphone is available. Connect a microphone and try again.")
        }
        latency = min(max(input.presentationLatency, 0), 0.25)
        input.installTap(onBus: 0, bufferSize: 1024, format: source) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / source.sampleRate)) + 32
            guard let self, let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var provided = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if provided {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                provided = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, error == nil else {
                self.end(throwing: DictationError("The microphone audio could not be converted. Try another input device."))
                return
            }
            guard output.frameLength > 0, let data = output.floatChannelData else { return }
            let frames = Int(output.frameLength)
            let channels = (0..<Int(target.channelCount)).map { Array(UnsafeBufferPointer(start: data[$0], count: frames)) }
            self.receive(channels, at: ProcessInfo.processInfo.systemUptime)
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.deviceChanged()
        }
        self.engine = engine
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw DictationError("Could not start the microphone. Check microphone access in System Settings.")
        }
        return stream
    }

    func receive(_ channels: [[Float]], at time: TimeInterval) {
        var level: Float?
        var callback: (@Sendable (Float) -> Void)?
        let finished = lock.withLock { () -> Bool in
            guard !ended else { return false }
            let processed = conditioner.process(channels)
            if !processed.audio.isEmpty, case .dropped = continuation.yield(processed.audio) {
                endLocked(DictationError("Your connection could not keep up with the microphone. No partial text was pasted. Please try again."))
                return true
            }
            guard let release else {
                level = processed.level
                callback = onLevel
                return false
            }
            guard time >= release.latest || (time >= release.earliest && conditioner.trailingQuiet >= Self.quietAfterSpeech) else { return false }
            endLocked(silenceError())
            return true
        }
        if let level { callback?(level) }
        if finished { DispatchQueue.main.async { [weak self] in self?.teardown() } }
    }

    func finish(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let earliest = time + latency
        lock.withLock { if release == nil { release = (earliest, earliest + Self.maximumTail) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + latency + Self.maximumTail + 0.4) { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.endLocked(self.silenceError()) }
            self.teardown()
        }
    }

    func stop() {
        lock.withLock { endLocked(nil) }
        teardown()
    }

    func deviceChanged() {
        lock.withLock { endLocked(release == nil ? DictationError("Your microphone changed during dictation. Please start a new recording.") : silenceError()) }
        DispatchQueue.main.async { [weak self] in self?.teardown() }
    }

    private func silenceError() -> Error? {
        conditioner.duration >= Self.minimumSilentDuration && !conditioner.heardSound ? DictationError.silentMicrophone(microphone?.name) : nil
    }

    private func end(throwing error: Error) {
        lock.withLock { endLocked(error) }
        DispatchQueue.main.async { [weak self] in self?.teardown() }
    }

    private func endLocked(_ error: Error?) {
        guard !ended else { return }
        ended = true
        if let error { continuation.finish(throwing: error) } else { continuation.finish() }
    }

    private func teardown() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
    }

    private static func resampledFormat(for source: AVAudioFormat) -> AVAudioFormat? {
        let rate = AudioConditioner.sampleRate
        guard source.channelCount > 2 else {
            return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: source.channelCount, interleaved: false)
        }
        guard let layout = source.channelLayout ?? AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | source.channelCount) else { return nil }
        return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, interleaved: false, channelLayout: layout)
    }

    deinit { stop() }
}
