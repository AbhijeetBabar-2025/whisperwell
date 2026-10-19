import Foundation
import WhisperwellCore
@preconcurrency import WhisperKit

/// `Whisperwell --transcribe <audio file>` runs a recording through the same pipeline as a
/// dictation (speech-to-text, then cleanup) and prints the result. For testing without a mic.
enum FileTranscription {
    /// `textBefore` simulates text already in the field above the cursor (`--before "..."`).
    static func run(path: String, textBefore: String = "") -> Int32 {
        let config: Config
        do {
            config = try Config.load()
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            return 1
        }
        print(config.speechSummary)
        print(config.cleanupSummary)

        let done = DispatchSemaphore(value: 0)
        let exitCode = ExitCode()
        Task.detached {
            do {
                let floats = try AudioProcessor.loadAudioAsFloatArray(fromPath: (path as NSString).expandingTildeInPath)
                let samples = floats.map { Int16(max(-1, min(1, $0)) * 32_767) }
                print(String(format: "audio: %.1fs", Double(samples.count) / Double(AudioFormat.sampleRate)))

                var onDevice: DictationPipeline.Transcribe?
                if config.asrProvider == .whisperkit {
                    let transcriber = OnDeviceTranscriber(config: config) { status in print("speech model: \(status)") }
                    onDevice = { @Sendable samples in try await transcriber.transcribe(samples: samples) }
                }
                let pipeline = try DictationPipeline.make(
                    config: config,
                    context: {
                        var context = TextContext(appName: "Notes", bundleID: "com.apple.Notes")
                        context.textBefore = textBefore
                        return context
                    }(),
                    onDevice: onDevice,
                    log: { print("note: \($0)") }
                )
                if CommandLine.arguments.contains("--race-preview"), let transcriber = onDevice {
                    // Reproduces a dictation: a live-preview pass on the first part of the audio
                    // is still running when the final transcription starts.
                    let partial = Array(samples.prefix(samples.count * 2 / 3))
                    let preview = Task { try await transcriber(partial) }
                    try await Task.sleep(nanoseconds: 50_000_000)
                    let final = try await transcriber(samples)
                    _ = try? await preview.value
                    print("race final: \(final)")
                }
                let start = Date()
                let text = try await pipeline.run(samples: samples)
                print(String(format: "took: %.1fs (includes loading the speech model)", Date().timeIntervalSince(start)))
                print("result: \(text)")
            } catch {
                fputs("error: \(error.localizedDescription)\n", stderr)
                exitCode.value = 1
            }
            done.signal()
        }
        done.wait()
        return exitCode.value
    }
}

private final class ExitCode: @unchecked Sendable {
    var value: Int32 = 0
}
