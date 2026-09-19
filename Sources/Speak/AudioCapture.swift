import AVFoundation
import SpeakCore

final class AudioCapture {
    private var engine: AVAudioEngine?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var configurationObserver: NSObjectProtocol?

    func start(onLevel: @escaping @Sendable (Float) -> Void) throws -> AsyncThrowingStream<Data, Error> {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: source, to: target) else {
            throw DictationError("No microphone is available. Connect a microphone and try again.")
        }
        let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(500))
        continuation = pair.continuation
        let continuation = pair.continuation
        input.installTap(onBus: 0, bufferSize: 1024, format: source) { buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 24000 / source.sampleRate)) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
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
                continuation.finish(throwing: DictationError("The microphone audio could not be converted. Try another input device."))
                return
            }
            guard output.frameLength > 0, let samples = output.int16ChannelData?[0] else { return }
            let count = Int(output.frameLength)
            var sum: Float = 0
            for i in 0..<count {
                let value = Float(samples[i]) / Float(Int16.max)
                sum += value * value
            }
            onLevel(min(1, sqrt(sum / Float(count)) * 7))
            let data = Data(bytes: samples, count: count * MemoryLayout<Int16>.size)
            if case .dropped = continuation.yield(data) {
                continuation.finish(throwing: DictationError("Your connection could not keep up with the microphone. No partial text was pasted. Please try again."))
            }
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { _ in
            continuation.finish(throwing: DictationError("Your microphone changed during dictation. Please start a new recording."))
        }
        self.engine = engine
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw DictationError("Could not start the microphone. Check microphone access in System Settings.")
        }
        return pair.stream
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        continuation?.finish()
        continuation = nil
    }

    deinit { stop() }
}
