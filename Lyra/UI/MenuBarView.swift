import SwiftUI

struct MenuBarView: View {
    @ObservedObject var engine: DictationEngine
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var modelManager = ModelManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header with status
            headerSection
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Alerts (permissions / errors) — surfaced prominently because without
            // Accessibility the app can record but cannot type into other apps.
            if !permissions.allPermissionsGranted || engine.modelLoadError != nil || engine.transcriptionError != nil || modelManager.downloadError != nil {
                alertsSection
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            // Last transcription
            if !engine.lastTranscription.isEmpty {
                transcriptionSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            Divider()
                .padding(.horizontal, 12)

            // Actions
            VStack(spacing: 2) {
                MenuButton(title: L10n.tr("History..."), icon: "clock.arrow.circlepath", shortcut: "Y") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                MenuButton(title: L10n.tr("Settings..."), icon: "gearshape", shortcut: ",") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                MenuButton(title: L10n.tr("Quit Lyra"), icon: "power", shortcut: "Q") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Version
            Text("v\(Bundle.main.appVersion)")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 6)
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            // Status orb
            ZStack {
                Circle()
                    .fill(statusGradient)
                    .frame(width: 36, height: 36)

                if engine.state == .recording {
                    Circle()
                        .stroke(Color.red.opacity(0.4), lineWidth: 2)
                        .frame(width: 44, height: 44)
                }

                Image(systemName: statusIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Lyra")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    // Model or Provider badge
                    if engine.isReadyToRecord {
                        Text(modelShortName)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.blue.opacity(0.12)))
                            .foregroundStyle(.blue)
                    }
                    if engine.isFallbackActive {
                        Text("Fallback")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        VStack(spacing: 6) {
            if !permissions.microphoneGranted {
                AlertRow(icon: "mic.slash.fill", text: "Microphone access needed", color: .orange) {
                    permissions.requestMicrophone()
                }
            }
            if !permissions.accessibilityGranted {
                AlertRow(icon: "hand.raised.fill", text: "Accessibility access needed — text cannot be typed without it", color: .orange) {
                    permissions.openAccessibilitySettings()
                }
            }
            if let error = engine.modelLoadError {
                AlertRow(icon: "exclamationmark.triangle.fill", text: error, color: .red) {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            if let error = engine.transcriptionError {
                AlertRow(icon: "waveform.badge.exclamationmark", text: error, color: .orange) {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            // Download failures must surface even when Settings (Model tab) isn't open.
            // Cleared automatically when the user retries (startDownload resets it).
            if let error = modelManager.downloadError {
                AlertRow(icon: "exclamationmark.arrow.triangle.2.circlepath", text: error, color: .orange) {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                    NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    // MARK: - Last Transcription

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tr("Last transcription"))
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)

            Text(engine.lastTranscription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary.opacity(0.5))
                )
        }
    }

    // MARK: - Status Helpers

    private var statusIcon: String {
        switch engine.state {
        case .idle: "waveform"
        case .recording: "mic.fill"
        case .processing: "brain.head.profile.fill"
        case .typing: "text.cursor"
        }
    }

    private var statusText: String {
        switch engine.state {
        case .idle:
            if !engine.isReadyToRecord {
                return L10n.tr("Loading...")
            }
            return String(format: L10n.tr("Ready — hold %@ to dictate"), hotkeyLabel)
        case .recording:
            return L10n.tr("Listening...")
        case .processing:
            return L10n.tr("Transcribing...")
        case .typing:
            return L10n.tr("Typing...")
        }
    }

    private var statusDotColor: Color {
        switch engine.state {
        case .idle: engine.isReadyToRecord ? .green : .orange
        case .recording: .red
        case .processing: .orange
        case .typing: .blue
        }
    }

    private var statusGradient: LinearGradient {
        let colors: [Color] = switch engine.state {
        case .idle: [.green.opacity(0.8), .green.opacity(0.5)]
        case .recording: [.red.opacity(0.9), .red.opacity(0.6)]
        case .processing: [.orange.opacity(0.8), .orange.opacity(0.5)]
        case .typing: [.blue.opacity(0.8), .blue.opacity(0.5)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var modelShortName: String {
        if settings.transcriptionProviderType == .api {
            return settings.apiPreset != .custom ? "\(settings.apiPreset.rawValue)" : "API"
        }
        let m = settings.selectedModel
        let base = m.split(separator: ".").first.map(String.init) ?? m
        let isQuantized = m.contains("q5") || m.contains("q8")
        return base.capitalized + (isQuantized ? " Q5" : "")
    }

    private var hotkeyLabel: String {
        KeyCodeNames.shortLabel(for: settings.hotkeyKeyCode)
    }
}

// MARK: - Alert Row

private struct AlertRow: View {
    let icon: String
    let text: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(color.opacity(0.35), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menu Button

private struct MenuButton: View {
    let title: String
    let icon: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Text("⌘\(shortcut)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuButtonStyle())
    }
}

private struct MenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.blue.opacity(0.8) : Color.clear)
            )
            .foregroundStyle(configuration.isPressed ? .white : .primary)
    }
}
