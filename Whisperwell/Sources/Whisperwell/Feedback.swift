import AppKit
import SwiftUI

/// What the user sees and hears during a dictation: a floating pill at the bottom of the
/// screen and short sounds. The pill never takes focus, so the paste lands in the right app.
@MainActor
final class Feedback {
    private let playSounds: Bool
    private let showIndicator: Bool
    private let model = IndicatorModel()
    private var hideWork: DispatchWorkItem?

    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: IndicatorView(model: model))
        return panel
    }()

    init(playSounds: Bool, showIndicator: Bool) {
        self.playSounds = playSounds
        self.showIndicator = showIndicator
    }

    /// Hotkey pressed: show the pill right away; the sound waits for real audio.
    func recordingRequested() {
        model.resetLevels()
        model.partial = ""
        show(.listening)
    }

    /// The mic is capturing. The sound is the cue to start talking.
    func listening() {
        play("Tink", volume: 0.25)
    }

    /// The words heard so far, shown while listening.
    func partial(_ text: String) {
        model.partial = text
    }

    func level(_ value: Float) {
        model.push(CGFloat(value))
    }

    func cancelled() {
        hide()
    }

    func transcribing() {
        play("Pop", volume: 0.2)
        show(.transcribing)
    }

    func inserted() {
        hide()
    }

    func notice(_ text: String) {
        show(.message(text, isError: false), hideAfter: 2)
    }

    /// The indicator keeps to one short line; long error messages stay in the menu.
    func failed(_ text: String) {
        play("Basso", volume: 0.3)
        let short = text.count <= 60 ? text : "Dictation failed. Details are in the Whisperwell menu."
        show(.message(short, isError: true), hideAfter: 5)
    }

    private func show(_ phase: IndicatorModel.Phase, hideAfter seconds: TimeInterval? = nil) {
        hideWork?.cancel()
        guard showIndicator else { return }
        model.phase = phase
        // Bottom center of the screen the pointer is on, just above the Dock.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 24))
        }
        panel.orderFrontRegardless()
        if let seconds {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
    }

    private func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }

    private func play(_ name: String, volume: Float) {
        guard playSounds, let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }
}

@MainActor
final class IndicatorModel: ObservableObject {
    enum Phase: Equatable {
        case listening
        case transcribing
        case message(String, isError: Bool)
    }

    static let barCount = 14
    @Published var phase: Phase = .listening
    @Published var levels: [CGFloat] = Array(repeating: 0, count: barCount)
    @Published var partial = ""

    func resetLevels() {
        levels = Array(repeating: 0, count: Self.barCount)
    }

    func push(_ level: CGFloat) {
        levels.removeFirst()
        levels.append(level)
    }
}

struct IndicatorView: View {
    @ObservedObject var model: IndicatorModel
    private let mint = Color(red: 0.42, green: 0.96, blue: 0.81)

    var body: some View {
        HStack(spacing: 12) {
            switch model.phase {
            case .listening:
                waveform
                label(model.partial.isEmpty ? "Listening…" : model.partial).fixedSize()
            case .transcribing:
                PulsingDots(color: mint)
                label("Transcribing…")
            case let .message(text, isError):
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundColor(isError ? .orange : mint)
                label(text).fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color(red: 0.07, green: 0.08, blue: 0.17).opacity(0.94)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                Capsule().fill(mint).frame(width: 4, height: 5 + level * 23)
            }
        }
        .frame(height: 28)
        .animation(.easeOut(duration: 0.08), value: model.levels)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
    }
}

/// Three dots that pulse in turn while the dictation is being transcribed.
struct PulsingDots: View {
    let color: Color
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .opacity(phase == index ? 1 : 0.35)
            }
        }
        .frame(height: 28)
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            phase = (phase + 1) % 3
        }
    }
}
