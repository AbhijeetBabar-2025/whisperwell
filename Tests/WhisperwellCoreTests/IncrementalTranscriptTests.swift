import XCTest
@testable import WhisperwellCore

/// Synthetic audio: "speech" is a loud tone, a pause is near-silence with a little noise.
private enum Audio {
    static let rate = AudioFormat.sampleRate

    static func speech(_ seconds: Double) -> [Int16] {
        (0..<Int(seconds * Double(rate))).map { i in Int16(8_000 * sin(Double(i) * 0.3)) }
    }

    static func pause(_ seconds: Double) -> [Int16] {
        (0..<Int(seconds * Double(rate))).map { i in Int16((i * 7_919) % 61) - 30 }
    }

    static func seconds(_ samples: Int) -> Double { Double(samples) / Double(rate) }

    /// Adds steady background noise (like a laptop fan) at about a tenth of the speech level.
    static func withRoomNoise(_ samples: [Int16]) -> [Int16] {
        var seed: UInt32 = 12_345
        return samples.map { s in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Int32(seed >> 16) % 2_001 - 1_000
            return Int16(clamping: Int32(s) + noise)
        }
    }
}

final class PausesTests: XCTestCase {
    func testCutsInTheMiddleOfAPauseAfterTheMinimumLength() {
        let audio = Audio.speech(9) + Audio.pause(0.6) + Audio.speech(3)
        let cut = Pauses.cut(in: audio, from: 0, minSeconds: 8, maxSeconds: 25)
        XCTAssertNotNil(cut)
        XCTAssertEqual(Audio.seconds(cut ?? 0), 9.3, accuracy: 0.05)
    }

    func testFindsPausesOverRoomNoise() {
        // The pause is only as quiet as the room, about 20 dB under the speech.
        let audio = Audio.withRoomNoise(Audio.speech(9) + Audio.pause(0.6) + Audio.speech(3))
        let cut = Pauses.cut(in: audio, from: 0, minSeconds: 8, maxSeconds: 25)
        XCTAssertEqual(Audio.seconds(cut ?? 0), 9.3, accuracy: 0.05)
        XCTAssertFalse(Pauses.hasSpeech(audio[(9 * 16_000 + 1_600)..<(9 * 16_000 + 8_000)], in: audio))
    }

    func testIgnoresPausesBeforeTheMinimumLength() {
        let audio = Audio.speech(3) + Audio.pause(0.6) + Audio.speech(6)
        XCTAssertNil(Pauses.cut(in: audio, from: 0, minSeconds: 8, maxSeconds: 25))
    }

    func testIgnoresGapsTooShortToBeAPause() {
        let audio = Audio.speech(9) + Audio.pause(0.1) + Audio.speech(3)
        XCTAssertNil(Pauses.cut(in: audio, from: 0, minSeconds: 8, maxSeconds: 25))
    }

    func testPrefersTheLongestPause() {
        let audio = Audio.speech(9) + Audio.pause(0.4) + Audio.speech(2) + Audio.pause(1.0) + Audio.speech(2)
        let cut = Pauses.cut(in: audio, from: 0, minSeconds: 8, maxSeconds: 25)
        XCTAssertEqual(Audio.seconds(cut ?? 0), 9 + 0.4 + 2 + 0.5, accuracy: 0.05)
    }

    func testSearchStartsAtTheGivenOffset() {
        // The first pause is longer, so it's the first cut.
        let audio = Audio.speech(9) + Audio.pause(0.8) + Audio.speech(9) + Audio.pause(0.6) + Audio.speech(1)
        let first = Pauses.cut(in: audio, from: 0, minSeconds: 8, maxSeconds: 25) ?? 0
        XCTAssertEqual(Audio.seconds(first), 9.4, accuracy: 0.05)
        let second = Pauses.cut(in: audio, from: first, minSeconds: 8, maxSeconds: 25)
        XCTAssertEqual(Audio.seconds(second ?? 0), 9 + 0.8 + 9 + 0.3, accuracy: 0.05)
    }

    func testStaysWithinTheMaximumLength() {
        let audio = Audio.speech(26) + Audio.pause(0.6) + Audio.speech(1)
        XCTAssertNil(Pauses.cut(in: audio, from: 0, minSeconds: 8, maxSeconds: 25))
    }

    func testNoPausesInSilenceOrSteadyNoise() {
        XCTAssertNil(Pauses.cut(in: Audio.pause(12), from: 0, minSeconds: 8, maxSeconds: 25))
        XCTAssertNil(Pauses.cut(in: Audio.speech(12), from: 0, minSeconds: 8, maxSeconds: 25))
    }

    func testHasSpeech() {
        let recording = Audio.speech(5) + Audio.pause(1)
        XCTAssertTrue(Pauses.hasSpeech(recording[0..<16_000], in: recording))
        XCTAssertFalse(Pauses.hasSpeech(recording[(5 * 16_000)...], in: recording))
        XCTAssertTrue(Pauses.hasSpeech(Audio.speech(1)[...], in: Audio.speech(1)), "all speech, no quiet part to compare with")
    }
}

@MainActor
final class IncrementalTranscriptTests: XCTestCase {
    /// Fake speech-to-text: answers with the length of the audio, in tenths of a second.
    final class FakeSpeech: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [Int] = []
        var failNext = false
        var delayNanoseconds: UInt64 = 0

        var calls: [Int] { lock.withLock { _calls } }

        func transcribe(_ samples: [Int16]) async throws -> String {
            lock.withLock { _calls.append(samples.count) }
            if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
            if lock.withLock({ defer { failNext = false }; return failNext }) {
                throw URLError(.timedOut)
            }
            return "[\(Int((Audio.seconds(samples.count) * 10).rounded()))]"
        }
    }

    private func make(_ speech: FakeSpeech) -> IncrementalTranscript {
        IncrementalTranscript(transcribe: { try await speech.transcribe($0) }, minSeconds: 8, maxSeconds: 25)
    }

    func testCommitsAtAPauseThenFinishesOnlyTheTail() async throws {
        let speech = FakeSpeech()
        let transcript = make(speech)
        let audio = Audio.speech(9) + Audio.pause(0.6) + Audio.speech(4)

        let shown = await transcript.update(samples: audio, preview: false)
        XCTAssertEqual(shown, "[93]")
        let text = try await transcript.finish(samples: audio)

        XCTAssertEqual(text, "[93] [43]")
        XCTAssertEqual(speech.calls.map(Audio.seconds).map { ($0 * 10).rounded() / 10 }, [9.3, 4.3])
    }

    func testPreviewShowsCommittedTextPlusTheRest() async {
        let speech = FakeSpeech()
        let transcript = make(speech)
        let audio = Audio.speech(9) + Audio.pause(0.6) + Audio.speech(4)

        _ = await transcript.update(samples: audio, preview: true)
        let shown = await transcript.update(samples: audio + Audio.speech(1), preview: true)
        XCTAssertEqual(shown, "[93] [53]")
    }

    func testNoPreviewPassWhenPreviewIsOff() async {
        let speech = FakeSpeech()
        let transcript = make(speech)
        let shown = await transcript.update(samples: Audio.speech(5), preview: false)
        XCTAssertNil(shown)
        XCTAssertEqual(speech.calls, [])
    }

    func testWithoutPausesFinishTranscribesEverything() async throws {
        let speech = FakeSpeech()
        let transcript = make(speech)
        let audio = Audio.speech(14)
        _ = await transcript.update(samples: audio, preview: false)
        let text = try await transcript.finish(samples: audio)
        XCTAssertEqual(text, "[140]")
        XCTAssertEqual(speech.calls, [audio.count])
    }

    func testFailedPieceIsRetriedAtFinish() async throws {
        let speech = FakeSpeech()
        let transcript = make(speech)
        let audio = Audio.speech(9) + Audio.pause(0.6) + Audio.speech(4)
        speech.failNext = true

        let shown = await transcript.update(samples: audio, preview: false)
        XCTAssertNil(shown)
        let text = try await transcript.finish(samples: audio)
        XCTAssertEqual(text, "[136]", "nothing was committed, so finish covers the whole recording")
    }

    func testSilentTailIsSkipped() async throws {
        let speech = FakeSpeech()
        let transcript = make(speech)
        let audio = Audio.speech(9) + Audio.pause(2)
        _ = await transcript.update(samples: audio, preview: false)
        let text = try await transcript.finish(samples: audio)
        XCTAssertEqual(text, "[100]")
        XCTAssertEqual(speech.calls.count, 1, "the quiet second after the cut isn't sent to Whisper")
    }

    func testFinishWaitsForAPieceInProgress() async throws {
        let speech = FakeSpeech()
        speech.delayNanoseconds = 200_000_000
        let transcript = make(speech)
        let audio = Audio.speech(9) + Audio.pause(0.6) + Audio.speech(4)

        let update = Task { await transcript.update(samples: audio, preview: false) }
        try await Task.sleep(nanoseconds: 50_000_000)
        let text = try await transcript.finish(samples: audio)
        _ = await update.value

        XCTAssertEqual(text, "[93] [43]", "the piece in progress is kept, not transcribed twice")
        XCTAssertEqual(speech.calls.count, 2)
    }

    func testFinishCancelsAPreviewPassInProgress() async throws {
        let speech = FakeSpeech()
        speech.delayNanoseconds = 2_000_000_000
        let transcript = make(speech)
        let audio = Audio.speech(5)

        let update = Task { await transcript.update(samples: audio, preview: true) }
        try await Task.sleep(nanoseconds: 50_000_000)
        speech.delayNanoseconds = 0
        let started = Date()
        let text = try await transcript.finish(samples: audio)
        let shown = await update.value

        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "didn't wait for the preview pass")
        XCTAssertNil(shown)
        XCTAssertEqual(text, "[50]")
    }

    func testUpdatesAfterFinishDoNothing() async throws {
        let speech = FakeSpeech()
        let transcript = make(speech)
        _ = try await transcript.finish(samples: Audio.speech(2))
        let shown = await transcript.update(samples: Audio.speech(12) + Audio.pause(1), preview: true)
        XCTAssertNil(shown)
        XCTAssertEqual(speech.calls.count, 1)
    }
}
