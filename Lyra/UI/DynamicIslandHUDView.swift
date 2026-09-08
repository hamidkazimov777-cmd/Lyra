import SwiftUI

/// Premium Dynamic Island & Apple Intelligence inspired floating HUD.
/// Compact and unobtrusive when idle, smoothly expands into a rich voice & live transcript surface during speech.
struct DynamicIslandHUDView: View {
    @ObservedObject var engine: DictationEngine
    @ObservedObject var analyzer: AudioLevelAnalyzer
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissionManager = PermissionManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovered = false

    var body: some View {
        ZStack {
            switch engine.state {
            case .idle:
                idleIsland
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
            case .recording:
                recordingIsland
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
            case .processing, .typing:
                processingIsland
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.78, blendDuration: 0.1), value: engine.state)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Idle State (Compact Pill)

    private var idleIsland: some View {
        HStack(spacing: 8) {
            // Constellation Lyra symbol / Voice dot
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.35, green: 0.78, blue: 1.0),
                                Color(red: 0.58, green: 0.45, blue: 1.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 9
                        )
                    )
                    .frame(width: 9, height: 9)
                    .blur(radius: isHovered ? 1 : 0)

                if isHovered {
                    Circle()
                        .stroke(Color(red: 0.35, green: 0.78, blue: 1.0).opacity(0.6), lineWidth: 1.5)
                        .frame(width: 15, height: 15)
                }
            }

            Text("Lyra")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize()

            if !permissionManager.accessibilityGranted {
                Button(action: {
                    permissionManager.requestAccessibility()
                    permissionManager.openAccessibilitySettings()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(L10n.tr("Enable Accessibility"))
                    }
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.orange))
                }
                .buttonStyle(.plain)
                .help(L10n.tr("Lyra requires Accessibility permission to type text at cursor. Click to open System Settings."))
            } else if let err = engine.transcriptionError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(err)
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .frame(maxWidth: 160)
            } else {
                Text(hotkeyDisplay)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            // Quick Record Button
            Button(action: {
                engine.toggleRecording()
            }) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.blue)
                    .padding(4)
                    .background(Circle().fill(Color.blue.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .help(L10n.tr("Click to start dictation") + " (\(hotkeyDisplay))")

            // Settings Button
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help(L10n.tr("Open Settings"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(islandBackground(isExpanded: false))
        .contentShape(Rectangle())
        .onTapGesture {
            engine.toggleRecording()
        }
        .contextMenu {
            Button(L10n.tr("Start Dictation")) {
                engine.toggleRecording()
            }
            Divider()
            Button(L10n.tr("Open Settings...")) {
                NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
            }
            Button(settings.isFloatingWidgetAlwaysVisible ? L10n.tr("Hide Floating Pill") : L10n.tr("Show Floating Pill")) {
                settings.isFloatingWidgetAlwaysVisible.toggle()
            }
            Divider()
            Button(L10n.tr("Quit Lyra")) {
                NSApp.terminate(nil)
            }
        }
        .onHover { isHovered = $0 }
    }

    // MARK: - Recording State (Expanded Island with Fluid Organic Waveform)

    /// Text to show while recording: the live-dictation stream if that mode is
    /// on, otherwise the display-only local preview.
    private var transcriptInProgress: String {
        engine.liveTranscription.isEmpty ? engine.previewTranscript : engine.liveTranscription
    }

    private var recordingIsland: some View {
        let isSmartEdit = engine.isSmartEditActive
        let accentColor: Color = isSmartEdit ? Color(red: 0.65, green: 0.35, blue: 1.0) : .red

        return HStack(spacing: 12) {
            // Recording state beacon (Click to Stop)
            Button(action: {
                engine.toggleRecording()
            }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(accentColor.opacity(0.5), lineWidth: 2)
                                .scaleEffect(1.4)
                        )

                    Text(engine.isHandsFreeActive ? L10n.tr("Stop") : (isSmartEdit ? L10n.tr("Smart Edit") : L10n.tr("Recording")))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                }
            }
            .buttonStyle(.plain)
            .help(L10n.tr("Click to stop dictation and insert text"))

            // Organic Fluid Voice Visualizer
            FluidOrganicSoundWave(levels: analyzer.levels, frequencyBands: analyzer.frequencyBands)
                .frame(width: 110, height: 22)

            // Live Transcript or Status text
            if !transcriptInProgress.isEmpty {
                // Grows with the text instead of truncating it: the window
                // resizes itself to fit (see RecordingHUDWindow.resizeToFit).
                Text(transcriptInProgress)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)
                    .animation(.easeOut(duration: 0.18), value: transcriptInProgress)
                    .transition(.opacity)
            } else if isSmartEdit {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10))
                    Text(L10n.tr("Say instruction..."))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(accentColor)
            } else {
                Text(settings.selectedLanguage.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Mode indicator (Cloud vs Local)
            providerBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(islandBackground(isExpanded: true, accentColor: accentColor))
    }

    // MARK: - Processing / Typing State

    private var processingIsland: some View {
        HStack(spacing: 10) {
            if engine.state == .processing {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 14, height: 14)
                Text(engine.isFallbackActive ? L10n.tr("Local Fallback...") : L10n.tr("Transcribing..."))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "text.cursor")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(L10n.tr("Inserting text..."))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.blue)
            }

            if !engine.lastTranscription.isEmpty {
                Text(engine.lastTranscription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 140, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(islandBackground(isExpanded: true, accentColor: engine.state == .processing ? .orange : .blue))
    }

    // MARK: - Helpers

    private var providerBadge: some View {
        let isAPI = settings.transcriptionProviderType == .api
        return Text(isAPI ? L10n.tr("Cloud") : L10n.tr("Local"))
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(isAPI ? Color.purple.opacity(0.18) : Color.blue.opacity(0.18)))
            .foregroundStyle(isAPI ? .purple : .blue)
    }

    private var hotkeyDisplay: String {
        settings.primaryHotkey.shortLabel
    }

    private func islandBackground(isExpanded: Bool, accentColor: Color? = nil) -> some View {
        Capsule()
            .fill(colorScheme == .dark ? Color.black.opacity(0.72) : Color.white.opacity(0.85))
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                (accentColor ?? Color(red: 0.35, green: 0.78, blue: 1.0)).opacity(isExpanded ? 0.6 : 0.35),
                                (accentColor ?? Color(red: 0.58, green: 0.45, blue: 1.0)).opacity(isExpanded ? 0.4 : 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isExpanded ? 1.2 : 0.8
                    )
            )
            .shadow(
                color: (accentColor ?? Color(red: 0.35, green: 0.78, blue: 1.0)).opacity(isExpanded ? 0.22 : 0.08),
                radius: isExpanded ? 12 : 6,
                x: 0,
                y: isExpanded ? 4 : 2
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.12),
                radius: 8,
                x: 0,
                y: 4
            )
    }
}

// MARK: - Fluid Organic SoundWave (Apple Intelligence & Siri style)

struct FluidOrganicSoundWave: View {
    let levels: [Float]
    let frequencyBands: [Float]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let currentLevel = CGFloat(averageLevel)

            ZStack {
                // Background ambient harmonic glow
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.78, blue: 1.0).opacity(0.25 * currentLevel),
                                Color(red: 0.58, green: 0.45, blue: 1.0).opacity(0.35 * currentLevel),
                                Color(red: 1.0, green: 0.35, blue: 0.65).opacity(0.25 * currentLevel)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: max(4, height * (0.3 + currentLevel * 0.7)))
                    .blur(radius: 4)

                // Multi-tone fluid wave lines
                HStack(spacing: 3) {
                    ForEach(0..<min(frequencyBands.count, 14), id: \.self) { i in
                        let band = CGFloat(frequencyBands[i])
                        let barH = max(3.0, (height * 0.9) * (0.15 + band * 0.85))

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.35, green: 0.80, blue: 1.0),
                                        Color(red: 0.60, green: 0.45, blue: 1.0),
                                        Color(red: 1.0, green: 0.40, blue: 0.70)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 3.5, height: barH)
                            .animation(.easeOut(duration: 0.08), value: band)
                    }
                }
            }
            .frame(width: width, height: height)
        }
    }

    private var averageLevel: Float {
        guard !levels.isEmpty else { return 0.1 }
        let sum = levels.suffix(10).reduce(0, +)
        return min(1.0, max(0.1, sum / Float(min(levels.count, 10)) * 2.5))
    }
}
