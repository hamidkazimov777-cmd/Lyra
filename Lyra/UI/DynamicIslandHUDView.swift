import SwiftUI

/// Geometry shared between the SwiftUI island and the AppKit panel that hosts it.
///
/// The panel is a single fixed size that never changes — every earlier problem
/// (the island sliding sideways, shadows sliced off at an invisible edge, the
/// resize/`windowDidMove` feedback loop) came from resizing the window to fit
/// its contents. Instead the window is deliberately larger than the island, the
/// island animates inside it, and the panel only needs to know which rectangle
/// is currently opaque so clicks outside it fall through to the app below.
enum HUDLayout {
    /// Fixed panel size. Wide and tall enough for the largest card plus room
    /// for its glow, so nothing is ever clipped by the window edge.
    static let panelSize = CGSize(width: 520, height: 210)

    /// Distance from the top of the panel to the top of the island.
    static let topInset: CGFloat = 10

    static let idleSize = CGSize(width: 132, height: 38)
    static let listeningSize = CGSize(width: 420, height: 134)
    static let compactCardSize = CGSize(width: 420, height: 116)

    static func contentSize(for state: DictationState) -> CGSize {
        switch state {
        case .idle: return idleSize
        case .recording: return listeningSize
        case .processing, .typing: return compactCardSize
        }
    }

    /// The island's rectangle in panel coordinates (AppKit, origin bottom-left),
    /// padded slightly so the border is comfortable to click and drag.
    static func hitRect(for state: DictationState) -> CGRect {
        let size = contentSize(for: state)
        let padding: CGFloat = 6
        return CGRect(
            x: (panelSize.width - size.width) / 2 - padding,
            y: panelSize.height - topInset - size.height - padding,
            width: size.width + padding * 2,
            height: size.height + padding * 2
        )
    }
}

/// The floating Lyra island.
///
/// Idle is a bare capsule — a dot and the word Lyra, nothing else. Clicking it
/// starts dictation; right-clicking opens the menu that used to live in the
/// inline buttons. During dictation it expands into a card with the live
/// transcript and a voice visualiser, and the border comes alive with a slowly
/// rotating colour sweep.
struct DynamicIslandHUDView: View {
    @ObservedObject var engine: DictationEngine
    @ObservedObject var analyzer: AudioLevelAnalyzer
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissionManager = PermissionManager.shared

    @State private var isHovered = false

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, HUDLayout.topInset)
    }

    private var island: some View {
        let size = HUDLayout.contentSize(for: engine.state)

        return ZStack {
            if engine.state == .idle {
                idleContent.transition(.opacity)
            } else {
                expandedContent.transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(shell)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture { engine.toggleRecording() }
        .contextMenu { menuItems }
        .onHover { isHovered = $0 }
        .help(helpText)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: engine.state)
    }

    // MARK: - Idle

    private var idleContent: some View {
        HStack(spacing: 8) {
            statusDot(color: dotColor, size: 9)

            Text("Lyra")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
        }
    }

    // MARK: - Expanded (listening / thinking / inserting)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                statusDot(color: accent, size: 8)

                Text("Lyra")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))

                Spacer(minLength: 8)

                Text(statusLabel)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(accent)
                    .lineLimit(1)
            }

            Text(displayText)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundColor(isPlaceholder ? .white.opacity(0.4) : .white.opacity(0.92))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 38, alignment: .topLeading)
                .animation(.easeOut(duration: 0.15), value: displayText)

            visualizer
                .frame(height: engine.state == .recording ? 30 : 18)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    /// A single animated surface for the whole card: one `TimelineView` drives
    /// both the waveform and the particles. Nesting several of them is what made
    /// the previous version pin the GPU.
    private var visualizer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let isRecording = engine.state == .recording
            let level = waveLevel
            let bands = analyzer.frequencyBands
            let tint = accent

            Canvas { graphics, size in
                if isRecording {
                    Self.drawWave(in: &graphics, size: size, time: t, level: level, bands: bands)
                } else {
                    Self.drawParticles(in: &graphics, size: size, time: t, color: tint)
                }
            }
        }
    }

    // MARK: - Shell

    private var cornerRadius: CGFloat {
        engine.state == .idle ? HUDLayout.idleSize.height / 2 : 24
    }

    /// Dark glass capsule. Deliberately opaque: `.ultraThinMaterial` on a
    /// floating panel forces the window server to re-capture everything behind
    /// the window on every frame, which is expensive enough to stall the whole
    /// machine when the card is also animating.
    private var shell: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(red: 0.04, green: 0.04, blue: 0.05).opacity(0.96))
            .overlay(border)
            .shadow(color: accent.opacity(engine.state == .idle ? 0.12 : 0.28), radius: 14, x: 0, y: 5)
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if engine.state == .idle {
            // Static gradient while idle — the island sits on screen all day and
            // must cost nothing when there is nothing to say.
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(red: 0.23, green: 0.51, blue: 0.96).opacity(isHovered ? 0.85 : 0.55),
                            Color(red: 0.55, green: 0.36, blue: 0.96).opacity(isHovered ? 0.85 : 0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
                .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
                let angle = context.date.timeIntervalSinceReferenceDate * 42
                shape.strokeBorder(
                    AngularGradient(colors: sweepColors, center: .center, angle: .degrees(angle)),
                    lineWidth: 1.4
                )
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Palette

    private var accent: Color {
        switch engine.state {
        case .idle:
            return Color(red: 0.23, green: 0.51, blue: 0.96)
        case .recording:
            return engine.isSmartEditActive
                ? Color(red: 0.85, green: 0.28, blue: 0.94)   // Smart Edit: magenta
                : Color(red: 0.23, green: 0.51, blue: 0.96)   // #3B82F6
        case .processing:
            return Color(red: 0.55, green: 0.36, blue: 0.96)  // #8B5CF6
        case .typing:
            return Color(red: 0.02, green: 0.71, blue: 0.83)  // #06B6D4
        }
    }

    /// Colours swept around the border while the island is active. Ends on the
    /// first colour again so the rotation has no visible seam.
    private var sweepColors: [Color] {
        [
            accent,
            Color(red: 0.38, green: 0.72, blue: 1.0),
            Color(red: 0.55, green: 0.36, blue: 0.96),
            accent.opacity(0.35),
            accent
        ]
    }

    private var dotColor: Color {
        if !permissionManager.accessibilityGranted || engine.transcriptionError != nil {
            return .orange
        }
        return Color(red: 0.36, green: 0.60, blue: 0.98)
    }

    private func statusDot(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0.55)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size
                )
            )
            .frame(width: size, height: size)
    }

    // MARK: - Text

    private var statusLabel: String {
        switch engine.state {
        case .idle:
            return ""
        case .recording:
            if engine.isSmartEditActive { return L10n.tr("Smart Edit") }
            if engine.isHandsFreeActive { return L10n.tr("Hands-free") }
            return L10n.tr("Listening...")
        case .processing:
            return engine.isFallbackActive ? L10n.tr("Local Fallback...") : L10n.tr("Analyzing...")
        case .typing:
            return L10n.tr("Inserting text...")
        }
    }

    /// Live stream when live dictation is on, otherwise the local preview.
    private var transcriptInProgress: String {
        engine.liveTranscription.isEmpty ? engine.previewTranscript : engine.liveTranscription
    }

    private var placeholderText: String {
        if engine.isSmartEditActive { return L10n.tr("Say instruction...") }
        return settings.selectedLanguage.displayName
    }

    private var rawText: String {
        switch engine.state {
        case .recording:
            return transcriptInProgress
        case .processing:
            return engine.lastTranscription.isEmpty ? transcriptInProgress : engine.lastTranscription
        default:
            return engine.lastTranscription
        }
    }

    private var isPlaceholder: Bool { rawText.isEmpty }

    private var displayText: String { isPlaceholder ? placeholderText : rawText }

    private var helpText: String {
        if !permissionManager.accessibilityGranted {
            return L10n.tr("Lyra requires Accessibility permission to type text at cursor. Click to open System Settings.")
        }
        if let err = engine.transcriptionError {
            return err
        }
        if engine.state == .idle {
            return L10n.tr("Click to start dictation") + " (\(settings.primaryHotkey.shortLabel))"
        }
        return L10n.tr("Click to stop dictation and insert text")
    }

    // MARK: - Menu
    //
    // The inline mic / settings buttons are gone from the capsule, so everything
    // they did lives here (and in the menu bar item).

    @ViewBuilder
    private var menuItems: some View {
        if !permissionManager.accessibilityGranted {
            Button(L10n.tr("Enable Accessibility")) {
                permissionManager.requestAccessibility()
                permissionManager.openAccessibilitySettings()
            }
            Divider()
        }

        Button(engine.state == .idle ? L10n.tr("Start Dictation") : L10n.tr("Stop")) {
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

    // MARK: - Canvas drawing

    /// Rolling loudness, 0...1, driving the wave amplitude.
    private var waveLevel: Double {
        let levels = analyzer.levels
        guard !levels.isEmpty else { return 0.1 }
        let recent = levels.suffix(8)
        let avg = recent.reduce(0, +) / Float(recent.count)
        return Double(min(1.0, max(0.08, avg * 2.6)))
    }

    /// Three flowing sine curves: amplitude from the microphone level, shape
    /// modulated by the analyzer's frequency bands.
    private static func drawWave(
        in graphics: inout GraphicsContext,
        size: CGSize,
        time: Double,
        level: Double,
        bands: [Float]
    ) {
        let mid = Double(size.height) / 2
        let maxAmp = Double(size.height) / 2 - 1

        for layer in 0..<3 {
            let amp = maxAmp * (0.16 + 0.84 * level) * (1.0 - Double(layer) * 0.26)
            let freq = 1.2 + Double(layer) * 0.7
            let phase = time * (1.1 + Double(layer) * 0.3) * (layer % 2 == 0 ? 1 : -1)

            var path = Path()
            var x: Double = 0
            while x <= Double(size.width) {
                let u = size.width > 0 ? x / Double(size.width) : 0
                // Taper both ends so the wave floats rather than being cut off.
                let taper = pow(sin(u * .pi), 0.6)
                let y = mid + sin(u * freq * 2 * .pi + phase) * amp * taper * envelope(bands, at: u)
                let point = CGPoint(x: x, y: y)
                if x == 0 { path.move(to: point) } else { path.addLine(to: point) }
                x += 4
            }

            let fade = 0.95 - Double(layer) * 0.25
            graphics.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.23, green: 0.51, blue: 0.96).opacity(fade),
                        Color(red: 0.45, green: 0.68, blue: 1.0).opacity(fade),
                        Color(red: 0.62, green: 0.42, blue: 0.98).opacity(fade)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: 2.4 - Double(layer) * 0.6, lineCap: .round)
            )
        }
    }

    /// Frequency-band energy at a horizontal position, interpolated so the curve
    /// breathes with the voice instead of stepping between bars.
    private static func envelope(_ bands: [Float], at u: Double) -> Double {
        guard bands.count > 1 else { return 1 }
        let pos = u * Double(bands.count - 1)
        let i = min(bands.count - 2, max(0, Int(pos)))
        let f = pos - Double(i)
        let value = Double(bands[i]) * (1 - f) + Double(bands[i + 1]) * f
        return 0.35 + 0.65 * min(1, value * 1.6)
    }

    /// Drifting dots for the thinking / inserting stages.
    private static func drawParticles(
        in graphics: inout GraphicsContext,
        size: CGSize,
        time: Double,
        color: Color
    ) {
        let count = 20
        let mid = Double(size.height) / 2

        for i in 0..<count {
            let u = Double(i) / Double(count - 1)
            let phase = time * 1.7 - u * 3.6
            let wave = 0.5 + 0.5 * sin(phase)
            let lift = sin(phase) * Double(size.height) * 0.3
            let radius = 1.4 + 1.3 * wave
            let x = 6 + u * (Double(size.width) - 12)
            let rect = CGRect(
                x: x - radius,
                y: mid + lift - radius,
                width: radius * 2,
                height: radius * 2
            )
            graphics.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.25 + 0.6 * wave)))
        }
    }
}
