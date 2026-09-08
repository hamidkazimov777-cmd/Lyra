import SwiftUI

struct AppearanceSection: View {
    @ObservedObject private var modelManager = ModelManager.shared

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

                Toggle(isOn: Binding(
                    get: { settings.livePreviewEnabled },
                    set: { enabled in
                        settings.livePreviewEnabled = enabled
                        guard enabled else { return }
                        // Explicit consent, not a silent background pull: the
                        // preview needs the voice-activity model, and a
                        // cloud-only user has no local Whisper model either.
                        if !modelManager.isModelDownloaded(ModelManager.ModelInfo.vadSilero),
                           !modelManager.isDownloading(.vadSilero) {
                            modelManager.startDownload(.vadSilero)
                        }
                        if !modelManager.hasUsableModel(for: settings.selectedLanguage) {
                            modelManager.startDownload(LanguageCatalog.defaultModel(for: settings.selectedLanguage))
                        }
                    }
                )) {
                    Text(L10n.tr("Show my words as I speak"))
                        .font(.system(size: 13))
                }
                .toggleStyle(.switch)

                Text(livePreviewCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var livePreviewCaption: String {
        guard settings.livePreviewEnabled else {
            return L10n.tr("The floating island expands to show a running transcript while you talk. Uses the local model for the preview; the text that gets inserted still comes from your configured provider.")
        }
        let hasVAD = modelManager.isModelDownloaded(ModelManager.ModelInfo.vadSilero)
        let hasWhisper = modelManager.hasUsableModel(for: settings.selectedLanguage)
        if hasVAD && hasWhisper {
            return L10n.tr("The floating island expands to show a running transcript while you talk. Uses the local model for the preview; the text that gets inserted still comes from your configured provider.")
        }
        if modelManager.isDownloading(.vadSilero) || !hasWhisper {
            return L10n.tr("Downloading the models the preview needs — it starts working when they finish.")
        }
        return L10n.tr("Requires the voice-activity model and a local Whisper model (Models section).")
    }
}
