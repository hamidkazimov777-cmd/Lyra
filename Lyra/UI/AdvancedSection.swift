import SwiftUI

struct AdvancedSection: View {
    @ObservedObject var settings: AppSettings
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(colorScheme: colorScheme) {
                CardHeader("Recording", subtitle: "Fine-tune capture behavior")
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Minimum recording duration")
                            .font(.system(size: 13))
                        Spacer()
                        Text(String(format: "%.1fs", settings.minimumRecordingDuration))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.minimumRecordingDuration, in: 0.0...1.0, step: 0.1)
                    Text("Recordings shorter than this are silently discarded.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader("Text Insertion", subtitle: "Method used to type text into active applications")
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
                    Text("Clipboard Paste (Cmd+V) is recommended and works reliably across all web browsers, Electron apps, messengers, and native software without dropped Cyrillic/Unicode characters. Your existing clipboard is automatically restored after pasting.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader("Reset")
                Button("Reset All Settings to Defaults") {
                    resetSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.red)
                Text("This does not delete downloaded models or dictation history.")
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
