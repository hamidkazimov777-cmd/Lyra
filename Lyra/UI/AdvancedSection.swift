import SwiftUI

struct AdvancedSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: DictationEngine
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Recording"), subtitle: L10n.tr("Fine-tune capture behavior"))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.tr("Minimum recording duration"))
                            .font(.system(size: 13))
                        Spacer()
                        Text(String(format: "%.1fs", settings.minimumRecordingDuration))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.minimumRecordingDuration, in: 0.0...1.0, step: 0.1)
                    Text(L10n.tr("Recordings shorter than this are silently discarded."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Text Insertion"), subtitle: L10n.tr("Method used to type text into active applications"))
                Picker("Method", selection: $settings.textInsertionMethod) {
                    ForEach(AppSettings.TextInsertionMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.radioGroup)
                .font(.system(size: 12))

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13))
                    Text(L10n.tr("Clipboard Paste (Cmd+V) is recommended and works reliably across all web browsers, Electron apps, messengers, and native software without dropped Cyrillic/Unicode characters. Your existing clipboard is automatically restored after pasting."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Microphone Start"), subtitle: L10n.tr("Reduce the delay before capture begins"))
                Toggle(isOn: Binding(
                    get: { settings.fastMicrophoneStartEnabled },
                    set: {
                        settings.fastMicrophoneStartEnabled = $0
                        engine.applyFastMicrophoneStartSetting()
                    }
                )) {
                    Text(L10n.tr("Fast microphone start"))
                        .font(.system(size: 13))
                }
                .toggleStyle(.switch)
                Text(L10n.tr("Keeps the audio graph prepared between recordings so the first syllable is not clipped. macOS may keep the microphone indicator visible while Lyra is idle."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Privacy"), subtitle: L10n.tr("Control what Lyra stores on this Mac"))
                Toggle(isOn: Binding(
                    get: { !settings.historyLoggingEnabled },
                    set: { settings.historyLoggingEnabled = !$0 }
                )) {
                    Text(L10n.tr("Private mode (do not save dictation history)"))
                        .font(.system(size: 13))
                }
                .toggleStyle(.switch)
                Text(L10n.tr("When enabled, transcriptions are never written to history.json on disk. Existing entries are kept until you clear them in the History tab."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Reset"))
                Button(L10n.tr("Reset All Settings to Defaults")) {
                    resetSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.red)
                Text(L10n.tr("This does not delete downloaded models or dictation history."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func resetSettings() {
        let domain = Bundle.main.bundleIdentifier ?? "com.lyra.Lyra"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        // Refresh published values by touching the shared instance.
        _ = AppSettings.shared
    }
}
