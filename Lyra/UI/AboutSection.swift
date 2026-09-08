import SwiftUI

struct AboutSection: View {
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 18) {
            LyraLogoView(size: 84)

            VStack(spacing: 5) {
                Text("Lyra")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Next-generation voice dictation for macOS")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Version \(Bundle.main.appVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            SettingsCard(colorScheme: colorScheme) {
                VStack(alignment: .leading, spacing: 10) {
                    AboutRow(title: "Concept", value: "Lyra Constellation & AI Voice")
                    AboutRow(title: "Architecture", value: "Hybrid Cloud API + Metal Whisper Fallback")
                    AboutRow(title: "Primary Language", value: "Русский язык (Priority #1)")
                    AboutRow(title: "License", value: "MIT")
                }
            }

            Text("Designed with Apple Intelligence aesthetics.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }
}

private struct AboutRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
        }
    }
}
