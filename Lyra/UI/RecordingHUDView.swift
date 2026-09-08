import SwiftUI

/// Floating recording HUD content.
///
/// Displays the current dictation state with a live voice visualization.
/// Designed to feel like a native, premium macOS overlay.
struct RecordingHUDView: View {
    @ObservedObject var engine: DictationEngine
    @ObservedObject var analyzer: AudioLevelAnalyzer

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            visualization
                .frame(width: 160, height: 80)

            statusText
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if !engine.lastTranscription.isEmpty, engine.state == .typing || engine.state == .processing {
                Text(engine.lastTranscription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
            }

            if let error = engine.transcriptionError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(background)
    }

    // MARK: - Visualization

    @ViewBuilder
    private var visualization: some View {
        ZStack {
            if engine.state == .idle {
                BreathingOrb(color: .gray)
            } else {
                FrequencyVisualizer(bands: analyzer.frequencyBands, color: stateColor)
                    .opacity(engine.state == .recording ? 1 : 0.5)

                ActiveOrb(color: stateColor, level: averageLevel)

                if engine.state == .processing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 44, height: 44)
                } else if engine.state == .typing {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(stateColor)
                        .frame(width: 44, height: 44)
                }
            }
        }
    }

    private var averageLevel: Float {
        guard !analyzer.frequencyBands.isEmpty else { return 0 }
        return analyzer.frequencyBands.reduce(0, +) / Float(analyzer.frequencyBands.count)
    }

    private var statusText: some View {
        Group {
            switch engine.state {
            case .idle:
                Text("Ready")
            case .recording:
                Text("Listening...")
            case .processing:
                Text("Transcribing...")
            case .typing:
                Text("Typing...")
            }
        }
    }

    private var stateColor: Color {
        switch engine.state {
        case .idle: return .gray
        case .recording: return .red
        case .processing: return .orange
        case .typing: return .blue
        }
    }

    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 20)
                .stroke(stateColor.opacity(0.4), lineWidth: engine.state == .idle ? 0.5 : 1.5)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.15), radius: 20, x: 0, y: 8)
    }
}

// MARK: - Active Orb

private struct ActiveOrb: View {
    let color: Color
    let level: Float

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.9), color.opacity(0.2)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 22
                )
            )
            .frame(width: 44, height: 44)
            .scaleEffect(0.7 + CGFloat(level) * 0.45)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.6), lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.08), value: level)
    }
}

// MARK: - Idle Orb

/// Static idle orb — the HUD is hidden in idle state, but the view stays in
/// memory. A repeating SwiftUI animation would keep the render loop alive and
/// waste CPU/battery even when the panel is off-screen, so this variant is
/// intentionally still.
private struct BreathingOrb: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color.opacity(0.3))
            .frame(width: 44, height: 44)
    }
}

// MARK: - Frequency Visualizer

/// Siri-style frequency-band visualization driven by an FFT of the microphone input.
private struct FrequencyVisualizer: View {
    let bands: [Float]
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bands.count, id: \.self) { index in
                FrequencyBar(value: CGFloat(bands[index]), color: color)
            }
        }
        .frame(height: 70)
    }
}

private struct FrequencyBar: View {
    let value: CGFloat
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(0.85))
            .frame(width: 6, height: barHeight)
            .animation(.easeOut(duration: 0.06), value: value)
    }

    private var barHeight: CGFloat {
        let minHeight: CGFloat = 3
        let maxHeight: CGFloat = 64
        return minHeight + (maxHeight - minHeight) * min(1, max(0, value))
    }
}
