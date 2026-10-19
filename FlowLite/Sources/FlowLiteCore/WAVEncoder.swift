import Foundation

/// The audio format FlowLite records in: what Whisper models and speech-to-text APIs expect.
public enum AudioFormat {
    public static let sampleRate = 16_000

    /// 16-bit samples to the -1...1 floats Whisper models take.
    public static func floatSamples(_ samples: [Int16]) -> [Float] {
        samples.map { Float($0) / 32_768 }
    }

    /// Loudness of a chunk of audio as 0...1 for a level meter: RMS mapped from -50 dB (silence) to 0 dB.
    public static func meterLevel(_ samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(Float(0)) { sum, s in
            let x = Float(s) / 32_768
            return sum + x * x
        } / Float(samples.count)
        guard meanSquare > 0 else { return 0 }
        let decibels = 10 * log10(meanSquare)
        return min(1, max(0, (decibels + 50) / 50))
    }

    /// WhisperKit never decodes the last `windowClipTime` seconds of audio (1 s by default),
    /// so a 1-second "hello there" came back empty. Trailing silence keeps all speech decodable.
    public static func paddedForWhisper(_ samples: [Float], clipSeconds: Float = 1.0) -> [Float] {
        samples + [Float](repeating: 0, count: Int(clipSeconds * Float(sampleRate)))
    }
}

/// Wraps 16-bit mono PCM samples in a standard 44-byte WAV header.
public enum WAVEncoder {
    public static func encode(samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = samples.count * 2
        var data = Data(capacity: 44 + dataSize)

        func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF")
        append(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        append(UInt32(16))              // fmt chunk size
        append(UInt16(1))               // PCM
        append(UInt16(1))               // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))  // byte rate
        append(UInt16(2))               // block align
        append(UInt16(16))              // bits per sample
        append("data")
        append(UInt32(dataSize))
        for sample in samples {
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}
