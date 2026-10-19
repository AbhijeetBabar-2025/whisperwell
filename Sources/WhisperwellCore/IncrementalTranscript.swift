import Foundation

/// Finds natural breaks in a recording, so it can be transcribed in pieces without splitting words.
public enum Pauses {
    static let frameLength = AudioFormat.sampleRate / 50 // 20 ms
    /// A quiet stretch at least this long counts as a pause.
    static let minPauseSeconds = 0.3
    /// Below this loudness (RMS) the recording has no clear speech, so nothing is judged quiet.
    static let minSpeechLevel: Float = 150
    /// Speech must be at least this many times louder than the background (12 dB) to tell pauses apart.
    static let minContrast: Float = 4

    /// A sample index in the middle of the longest pause that lies between `minSeconds` and
    /// `maxSeconds` after `from`, or nil if there isn't one yet.
    public static func cut(in samples: [Int16], from: Int, minSeconds: Double, maxSeconds: Double) -> Int? {
        let levels = frameLevels(samples)
        guard let threshold = quietThreshold(levels) else { return nil }
        let rate = Double(AudioFormat.sampleRate)
        let earliest = from + Int(minSeconds * rate)
        let latest = from + Int(maxSeconds * rate)
        let minFrames = Int((minPauseSeconds * rate).rounded()) / frameLength

        var best: (cut: Int, frames: Int)?
        var runStart: Int?
        for frame in (from + frameLength - 1) / frameLength...levels.count {
            let quiet = frame < levels.count && levels[frame] < threshold
            if quiet {
                if runStart == nil { runStart = frame }
                continue
            }
            guard let start = runStart else { continue }
            runStart = nil
            let frames = frame - start
            let cut = (start + frame) * frameLength / 2
            guard frames >= minFrames, cut >= earliest, cut <= latest else { continue }
            if frames >= (best?.frames ?? 0) { best = (cut, frames) }
        }
        return best?.cut
    }

    /// Whether `part` contains anything louder than the pauses in `recording`. True when the
    /// recording is too quiet or too uniform to tell, so speech is never thrown away on a guess.
    public static func hasSpeech(_ part: ArraySlice<Int16>, in recording: [Int16]) -> Bool {
        guard let threshold = quietThreshold(frameLevels(recording)) else { return true }
        let loudFrames = frameLevels(Array(part)).filter { $0 >= threshold }.count
        return loudFrames >= 5 // 100 ms
    }

    /// RMS loudness of each 20 ms frame, counted from the start of the recording.
    static func frameLevels(_ samples: [Int16]) -> [Float] {
        stride(from: 0, to: samples.count - frameLength + 1, by: frameLength).map { start in
            var sum: Float = 0
            for s in samples[start..<start + frameLength] {
                let x = Float(s)
                sum += x * x
            }
            return (sum / Float(frameLength)).squareRoot()
        }
    }

    /// The loudness below which a frame counts as quiet: halfway, in decibels, between the
    /// background (the quietest few percent of frames) and speech (the loudest tenth). Adapts to
    /// room noise and mic gain. Nil when the recording has no clear speech or no clear background.
    static func quietThreshold(_ levels: [Float]) -> Float? {
        guard !levels.isEmpty else { return nil }
        let sorted = levels.sorted()
        let background = max(sorted[sorted.count * 3 / 100], 1)
        let speech = sorted[sorted.count * 9 / 10]
        guard speech >= minSpeechLevel, speech >= background * minContrast else { return nil }
        return (background * speech).squareRoot()
    }

    /// Numbers behind the pause decisions, for the log. Loudness only, never content.
    public static func summary(_ samples: [Int16]) -> String {
        let sorted = frameLevels(samples).sorted()
        guard !sorted.isEmpty else { return "no audio" }
        let background = Int(sorted[sorted.count * 3 / 100])
        let speech = Int(sorted[sorted.count * 9 / 10])
        let threshold = quietThreshold(sorted).map { String(Int($0)) } ?? "none (no clear speech or background)"
        return "background \(background), speech \(speech), quiet below \(threshold)"
    }
}

/// Transcribes a recording in pieces while it's still being recorded, cutting at pauses.
/// When the hotkey is released only the audio after the last cut is left to transcribe,
/// so long dictations paste about as fast as short ones.
public actor IncrementalTranscript {
    public typealias Transcribe = @Sendable ([Int16]) async throws -> String

    private let transcribe: Transcribe
    private let minSeconds: Double
    private let maxSeconds: Double
    /// Text of the finished pieces, and how many samples they cover.
    private var pieces: [String] = []
    private var committed = 0
    private var pass: (task: Task<String?, Never>, commits: Bool)?
    private var finished = false

    /// How much audio is already transcribed, in seconds. For the log.
    public var committedSeconds: Double { Double(committed) / Double(AudioFormat.sampleRate) }

    /// Pieces are `minSeconds` to `maxSeconds` long; Whisper reads audio in 30-second windows.
    public init(transcribe: @escaping Transcribe, minSeconds: Double = 8, maxSeconds: Double = 25) {
        self.transcribe = transcribe
        self.minSeconds = minSeconds
        self.maxSeconds = maxSeconds
    }

    /// One pass over the audio recorded so far. If there's a pause after enough new speech,
    /// transcribes up to it and keeps the result. Otherwise, when `preview` is set, transcribes
    /// the newest audio for display only. Returns the text to show, or nil if nothing ran.
    public func update(samples: [Int16], preview: Bool) async -> String? {
        guard !finished, pass == nil else { return nil }
        let start = committed
        let cut = Pauses.cut(in: samples, from: start, minSeconds: minSeconds, maxSeconds: maxSeconds)
        if cut == nil, !preview { return nil }

        let piece: [Int16]
        if let cut {
            piece = Array(samples[start..<cut])
            if !Pauses.hasSpeech(piece[...], in: samples) {
                committed = cut // a long silence: nothing to transcribe
                return pieces.joined(separator: " ")
            }
        } else {
            let recent = max(start, samples.count - LivePreview.maxSeconds * AudioFormat.sampleRate)
            piece = Array(samples[recent...])
        }
        let transcribe = self.transcribe
        // Runs on this actor, so the piece is recorded before anyone waiting on it resumes.
        let task = Task { () -> String? in
            guard let text = try? await transcribe(piece) else { return nil }
            if let cut {
                if !text.isEmpty { self.pieces.append(text) }
                self.committed = cut
                return self.pieces.joined(separator: " ")
            }
            guard !self.finished else { return nil }
            return (self.pieces + [text]).filter { !$0.isEmpty }.joined(separator: " ")
        }
        pass = (task, cut != nil)
        let shown = await task.value
        pass = nil
        return shown
    }

    /// Call once recording has stopped, with the whole recording. Keeps a piece that's being
    /// transcribed, drops a preview pass, transcribes the rest, and returns the full transcript.
    public func finish(samples: [Int16]) async throws -> String {
        finished = true
        if let pass {
            if pass.commits {
                _ = await pass.task.value
            } else {
                pass.task.cancel()
            }
        }
        let rest = samples[min(committed, samples.count)...]
        if !rest.isEmpty, Pauses.hasSpeech(rest, in: samples) {
            let text = try await transcribe(Array(rest))
            if !text.isEmpty { pieces.append(text) }
        }
        return pieces.joined(separator: " ")
    }
}
