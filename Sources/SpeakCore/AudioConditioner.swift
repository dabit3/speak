import Foundation

public struct AudioConditioner {
    public static let sampleRate = 24_000.0
    public static let targetLevel: Float = 0.125
    public static let maximumGain: Float = 8
    public static let silenceThreshold: Float = 0.0001
    static let frameLength = 240
    static let speechFloor: Float = 0.002
    static let speechMargin: Float = 3.16
    static let gainStep: Float = 1.122
    static let speechDecay: Float = 0.9931
    static let headroom: Float = 0.9
    static let noiseBlockFrames = 10
    static let noiseWindowBlocks = 15
    static let speechOnsetFrames = 5
    public private(set) var peak: Float = 0
    public private(set) var gain: Float = 1
    public private(set) var samples = 0
    private var quietSamples = 0
    private var speechFrames = 0
    private var channelLevels: [Float] = []
    private var speechLevel: Float?
    private var noiseMinima: [Float] = []
    private var blockMinimum = Float.infinity
    private var blockFrames = 0

    public init() {}

    public var heardSound: Bool { peak >= Self.silenceThreshold }
    public var duration: TimeInterval { Double(samples) / Self.sampleRate }
    public var trailingQuiet: TimeInterval { Double(quietSamples) / Self.sampleRate }

    public mutating func process(_ channels: [[Float]]) -> (audio: Data, level: Float) {
        let mono = mix(channels)
        guard !mono.isEmpty else { return (Data(), 0) }
        var output: [Int16] = []
        output.reserveCapacity(mono.count)
        var energy: Float = 0
        var start = 0
        while start < mono.count {
            let frame = mono[start..<min(start + Self.frameLength, mono.count)]
            let next = nextGain(for: frame)
            let first = min(gain, next)
            for (offset, sample) in frame.enumerated() {
                let scale = first + (next - first) * Float(offset + 1) / Float(frame.count)
                let value = max(-1, min(1, sample * scale))
                energy += value * value
                output.append(Int16((value * Float(Int16.max)).rounded()))
            }
            gain = next
            start += frame.count
        }
        samples += mono.count
        let audio = output.withUnsafeBufferPointer { Data(buffer: $0) }
        return (audio, min(1, (energy / Float(mono.count)).squareRoot() * 7))
    }

    private mutating func mix(_ channels: [[Float]]) -> [Float] {
        guard let count = channels.map(\.count).min(), count > 0 else { return [] }
        if channels.count == 1 { return channels[0] }
        let levels = channels.map { Self.rms($0[0..<count]) }
        channelLevels = channelLevels.count == channels.count ? zip(channelLevels, levels).map { ($0 + $1) / 2 } : levels
        let total = channelLevels.reduce(0, +)
        var mono = [Float](repeating: 0, count: count)
        for (channel, level) in zip(channels, channelLevels) {
            let weight = total > 0 ? level / total : 1 / Float(channels.count)
            guard weight > 0 else { continue }
            for index in 0..<count { mono[index] += channel[index] * weight }
        }
        if count >= Self.frameLength, let strongest = levels.indices.max(by: { levels[$0] < levels[$1] }),
           levels[strongest] > Self.silenceThreshold, Self.rms(mono[...]) < levels[strongest] * 0.1 {
            return Array(channels[strongest].prefix(count))
        }
        return mono
    }

    private mutating func nextGain(for frame: ArraySlice<Float>) -> Float {
        let level = Self.rms(frame)
        let framePeak = frame.reduce(0) { max($0, abs($1)) }
        peak = max(peak, framePeak)
        trackNoise(level)
        if level > max(noiseFloor * Self.speechMargin, Self.speechFloor) {
            speechLevel = max(level, (speechLevel ?? 0) * Self.speechDecay)
            speechFrames += 1
            quietSamples = 0
        } else {
            quietSamples += frame.count
        }
        var next: Float = 1
        if let speechLevel, speechFrames >= Self.speechOnsetFrames { next = min(Self.maximumGain, max(1, Self.targetLevel / speechLevel)) }
        if next > gain { next = min(next, gain * Self.gainStep) }
        if framePeak > 0 { next = min(next, max(1, Self.headroom / framePeak)) }
        return next
    }

    private mutating func trackNoise(_ level: Float) {
        if level > 0.000001 { blockMinimum = min(blockMinimum, level) }
        blockFrames += 1
        guard blockFrames == Self.noiseBlockFrames else { return }
        if blockMinimum.isFinite { noiseMinima = Array((noiseMinima + [blockMinimum]).suffix(Self.noiseWindowBlocks)) }
        blockMinimum = .infinity
        blockFrames = 0
    }

    private var noiseFloor: Float {
        let floor = min(noiseMinima.min() ?? .infinity, blockMinimum)
        return floor.isFinite ? floor : 0
    }

    static func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }
}
