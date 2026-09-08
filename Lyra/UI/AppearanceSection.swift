import SwiftUI

struct AppearanceSection: View {
    @ObservedObject var settings: AppSettings
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Floating Overlay (Dynamic Island)"), subtitle: L10n.tr("Apple Intelligence and Aqua Voice inspired indicator"))

                Toggle(L10n.tr("Always show compact pill in idle state"), isOn: $settings.isFloatingWidgetAlwaysVisible)
                    .font(.system(size: 13))

                Text(L10n.tr("A subtle capsule remains on your screen showing Lyra's status. It expands organically with live audio waves when you start speaking."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .padding(.vertical, 4)

                Toggle(L10n.tr("Show expanded overlay during recording"), isOn: $settings.showRecordingHUD)
                    .font(.system(size: 13))

                Text(L10n.tr("Shows real-time voice waveform and live transcript as you dictate."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Theme"), subtitle: L10n.tr("Lyra seamlessly adopts native macOS styling"))
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.05, green: 0.07, blue: 0.18),
                                    Color(red: 0.12, green: 0.10, blue: 0.28)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(red: 0.35, green: 0.78, blue: 1.0).opacity(0.35), lineWidth: 1)
                        )
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "sparkles")
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("System Dynamic"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(L10n.tr("Adapts automatically between Light, Dark, and High Contrast."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }
        }
    }
}
