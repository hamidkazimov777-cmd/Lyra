import SwiftUI

struct HotkeysSection: View {
    @ObservedObject var settings: AppSettings
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Activation Key"), subtitle: L10n.tr("Global shortcut to trigger dictation anywhere"))
                HotkeyRecorder(binding: $settings.primaryHotkey, colorScheme: colorScheme)

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("Default is Left Option (⌥). You can pick any key, or a combination — hold the modifiers and press the key, e.g. fn + `."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Dictation Mode"), subtitle: L10n.tr("Choose how the hotkey activates dictation"))
                Picker(L10n.tr("Dictation Mode"), selection: $settings.hotkeyMode) {
                    Text(L10n.tr("Hold or Tap")).tag(AppSettings.HotkeyMode.pushToTalk)
                    Text(L10n.tr("Toggle Only")).tag(AppSettings.HotkeyMode.toggle)
                }
                .pickerStyle(.segmented)
                .font(.system(size: 13))

                if settings.hotkeyMode == .pushToTalk {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.tr("Both on one key"))
                                .font(.system(size: 12, weight: .semibold))
                            Text(L10n.tr("Hold the key while speaking and release to insert — or tap it quickly to keep recording hands-free, then tap again to finish. You do not have to choose between the two."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)

                    // With a dedicated hands-free key assigned, a quick tap of the
                    // main key no longer latches anything, so the threshold has
                    // nothing left to control — say so instead of showing a
                    // slider that does nothing.
                    if settings.handsFreeHotkey.isAssigned {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(L10n.tr("You have a separate hands-free key, so the main key is hold-to-talk only — tapping it will not leave the microphone running."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 6)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(L10n.tr("Hold / tap threshold"))
                                    .font(.system(size: 12))
                                Spacer()
                                Text(String(format: "%.2fs", settings.handsFreeTapThreshold))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $settings.handsFreeTapThreshold, in: 0.15...1.0, step: 0.05)
                            Text(L10n.tr("A press shorter than this counts as a tap and latches hands-free recording; anything longer is treated as hold-to-talk."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 6)
                    }
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

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Hands-Free Key"), subtitle: L10n.tr("Optional second shortcut that always toggles hands-free"))
                HotkeyRecorder(
                    binding: $settings.handsFreeHotkey,
                    colorScheme: colorScheme,
                    allowsUnassigned: true
                )
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("Press once to start speaking with your hands off the keyboard, press again to finish. Works no matter which mode the main key is in. A combination such as fn + ` is a good choice here."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
    }
}
