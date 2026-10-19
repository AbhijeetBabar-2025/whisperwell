import AVFoundation
import WhisperwellCore

/// Records the default microphone and converts it to 16 kHz mono 16-bit PCM,
/// the format speech-to-text services expect.
final class AudioRecorder {
    /// Called on the main thread when the first audio arrives, i.e. the mic is really capturing.
    var onFirstAudio: (() -> Void)?
    /// Called on the main thread with the loudness (0...1) of each chunk, for a level meter.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var heardFirstAudio = false
    private(set) var isRecording = false

    /// Sets up the audio engine ahead of time so pressing the hotkey starts capture faster.
    /// Doesn't open the microphone, so the mic indicator stays off.
    func warmUp() {
        _ = engine.inputNode
        engine.prepare()
    }

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        guard
            let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(AudioFormat.sampleRate),
                                             channels: 1, interleaved: true),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            throw RecorderError.converterUnavailable(inputFormat.description)
        }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        heardFirstAudio = false
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, converter: converter, outputFormat: outputFormat)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.engineStart(error.localizedDescription)
        }
        isRecording = true
    }

    /// The audio captured so far, without stopping. For the live preview.
    func snapshot() -> [Int16] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    /// Stops recording and returns everything captured since `start()`.
    func stop() -> [Int16] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.prepare() // stay ready for the next dictation
        isRecording = false
        lock.lock()
        defer { lock.unlock() }
        let captured = samples
        samples = []
        return captured
    }

    // Runs on the audio thread.
    private func append(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = output.int16ChannelData else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
        lock.lock()
        samples.append(contentsOf: chunk)
        let isFirst = !heardFirstAudio
        heardFirstAudio = true
        lock.unlock()

        let level = AudioFormat.meterLevel(chunk)
        DispatchQueue.main.async { [weak self] in
            if isFirst { self?.onFirstAudio?() }
            self?.onLevel?(level)
        }
    }
}

enum RecorderError: LocalizedError {
    case noInputDevice
    case converterUnavailable(String)
    case engineStart(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone found. Pick an input device in System Settings › Sound."
        case let .converterUnavailable(format):
            return "Can't convert the microphone's audio format (\(format)) to 16 kHz mono."
        case let .engineStart(reason):
            return "Couldn't start the microphone: \(reason). Check System Settings › Privacy & Security › Microphone."
        }
    }
}
