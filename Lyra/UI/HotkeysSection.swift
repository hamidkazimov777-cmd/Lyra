import SwiftUI

struct HotkeysSection: View {
    @ObservedObject var settings: AppSettings
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Activation Key"), subtitle: L10n.tr("Global shortcut to trigger dictation anywhere"))
                HotkeyRecorder(keyCode: $settings.hotkeyKeyCode, colorScheme: colorScheme)

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("Default is Left Option (⌥). You can change it to Right Option, Fn, Control, or any key."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Dictation Mode"), subtitle: L10n.tr("Choose how the hotkey activates dictation"))
                Picker(L10n.tr("Dictation Mode"), selection: $settings.hotkeyMode) {
                    Text(L10n.tr("Push-to-Talk")).tag(AppSettings.HotkeyMode.pushToTalk)
                    Text(L10n.tr("Hands-Free (Toggle)")).tag(AppSettings.HotkeyMode.toggle)
                }
                .pickerStyle(.segmented)
                .font(.system(size: 13))

                if settings.hotkeyMode == .pushToTalk {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.tr("Hold & Release"))
                                .font(.system(size: 12, weight: .semibold))
                            Text(L10n.tr("Hold the key while speaking. When you release it, dictation stops and text is typed at your cursor immediately."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.tr("Click to Start, Click to Stop"))
                                .font(.system(size: 12, weight: .semibold))
                            Text(L10n.tr("Press the hotkey once to start recording. Speak freely with your hands off the keyboard. Press the key a second time to stop and insert text."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
