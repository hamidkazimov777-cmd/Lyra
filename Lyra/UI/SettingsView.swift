import SwiftUI
import Carbon.HIToolbox

// MARK: - Settings Window

struct SettingsView: View {
    @ObservedObject var engine: DictationEngine
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var modelManager = ModelManager.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @ObservedObject private var l10n = LocalizationService.shared
    @State private var selectedSection: SettingsSection = .general
    @Environment(\.colorScheme) private var colorScheme

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case dictation = "Dictation"
        case provider = "Provider"
        case appearance = "Appearance"
        case hotkeys = "Hotkeys"
        case history = "History"
        case advanced = "Advanced"
        case about = "About"

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .general: return L10n.tr("General")
            case .dictation: return L10n.tr("Dictation")
            case .provider: return L10n.tr("Provider")
            case .appearance: return L10n.tr("Appearance")
            case .hotkeys: return L10n.tr("Hotkeys")
            case .history: return L10n.tr("History")
            case .advanced: return L10n.tr("Advanced")
            case .about: return L10n.tr("About")
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .dictation: return "waveform"
            case .provider: return "network"
            case .appearance: return "paintbrush.fill"
            case .hotkeys: return "keyboard.fill"
            case .history: return "clock.arrow.circlepath"
            case .advanced: return "slider.horizontal.3"
            case .about: return "sparkles"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailPane
        }
        .frame(width: 660, height: 520)
        .background(colorScheme == .dark ? Color(.windowBackgroundColor) : Color(.controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tr("Settings"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)

            ForEach(SettingsSection.allCases) { section in
                SidebarRow(
                    title: section.localizedTitle,
                    icon: section.icon,
                    isSelected: selectedSection == section,
                    colorScheme: colorScheme
                )
                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { selectedSection = section } }
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(engine.isReadyToRecord ? .green : .orange)
                    .frame(width: 7, height: 7)
                Text(engine.isReadyToRecord ? L10n.tr("Ready") : L10n.tr("Loading..."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("v\(Bundle.main.appVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 170)
        .background(
            colorScheme == .dark
                ? Color.black.opacity(0.15)
                : Color(.windowBackgroundColor)
        )
    }

    // MARK: - Detail Pane

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedSection.localizedTitle)
                    .font(.system(size: 20, weight: .bold))
                    .padding(.bottom, 16)

                switch selectedSection {
                case .general:
                    GeneralSection(settings: settings, colorScheme: colorScheme)
                case .dictation:
                    VStack(spacing: 16) {
                        SpeechSection(settings: settings, modelManager: modelManager, engine: engine, colorScheme: colorScheme)
                        VocabularySection(settings: settings, colorScheme: colorScheme)
                    }
                case .provider:
                    ProviderSection(settings: settings, coordinator: engine.coordinator, modelManager: modelManager, engine: engine, colorScheme: colorScheme)
                case .appearance:
                    AppearanceSection(settings: settings, colorScheme: colorScheme)
                case .hotkeys:
                    HotkeysSection(settings: settings, colorScheme: colorScheme)
                case .history:
                    HistorySection()
                case .advanced:
                    AdvancedSection(settings: settings, colorScheme: colorScheme)
                case .about:
                    AboutSection(colorScheme: colorScheme)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    isSelected
                        ? AnyShapeStyle(LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                : nil
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Card

struct SettingsCard<Content: View>: View {
    let colorScheme: ColorScheme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }
}

struct CardHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - General Section

private struct GeneralSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var audioDevices: AudioDeviceManager = .shared
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Interface Language"), subtitle: L10n.tr("Choose application display language"))
                Picker(L10n.tr("Interface Language"), selection: $settings.interfaceLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .font(.system(size: 13))
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Microphone"), subtitle: L10n.tr("Audio input device for recording"))
                Picker(L10n.tr("Input device"), selection: Binding(
                    get: { settings.selectedAudioDeviceUID ?? "" },
                    set: { settings.selectedAudioDeviceUID = $0.isEmpty ? nil : $0 }
                )) {
                    Text(L10n.tr("System Default")).tag("")
                    ForEach(audioDevices.inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .font(.system(size: 13))
                .onAppear { audioDevices.refreshDevices() }
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Preferences"))
                Toggle(L10n.tr("Sound feedback"), isOn: $settings.soundFeedbackEnabled)
                    .font(.system(size: 13))
                Toggle(L10n.tr("Launch at login"), isOn: $settings.launchAtLogin)
                    .font(.system(size: 13))
                    .onChange(of: settings.launchAtLogin) { newValue in
                        LaunchAtLoginHelper.setEnabled(newValue)
                    }
            }
        }
    }
}

// MARK: - Model Section

private struct ModelSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var modelManager: ModelManager
    let engine: DictationEngine
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            // Recommended quantized models
            CardHeader(L10n.tr("Recommended (Quantized)"), subtitle: L10n.tr("Smaller, faster, near-identical accuracy"))

            ForEach(LanguageCatalog.recommendedModels(for: settings.selectedLanguage)) { model in
                modelCard(model)
            }

            // VAD model
            CardHeader(L10n.tr("Voice Activity Detection"), subtitle: L10n.tr("Trims silence for faster inference (2 MB)"))

            let vadDownloaded = modelManager.isModelDownloaded(ModelManager.ModelInfo.vadSilero)
            SettingsCard(colorScheme: colorScheme) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.cyan.opacity(0.7), .cyan.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                        Image(systemName: "waveform.path")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Silero VAD")
                            .font(.system(size: 13, weight: .semibold))
                        Text(L10n.tr("Auto-trims silence before transcription"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if vadDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 18))
                    } else if modelManager.isDownloading(.vadSilero) {
                        downloadingControls(for: .vadSilero)
                    } else {
                        Button(L10n.tr("Download")) {
                            modelManager.startDownload(.vadSilero)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // Full precision models (collapsible)
            DisclosureGroup {
                VStack(spacing: 10) {
                    ForEach(LanguageCatalog.models(for: settings.selectedLanguage).filter { !$0.isQuantized }) { model in
                        modelCard(model)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(L10n.tr("Full Precision Models"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let error = modelManager.downloadError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func modelCard(_ model: ModelManager.ModelInfo) -> some View {
        let isSelected = isModelSelected(model)
        let isDownloaded = modelManager.isModelDownloaded(model)

        SettingsCard(colorScheme: colorScheme) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tierGradient(for: model))
                        .frame(width: 36, height: 36)
                    Text(tierEmoji(for: model))
                        .font(.system(size: 16))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.name)
                            .font(.system(size: 13, weight: .semibold))
                        if model.isQuantized {
                            Text("Q5")
                                .font(.system(size: 9, weight: .bold))

                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.orange.opacity(0.15)))
                                .foregroundStyle(.orange)
                        }
                        if isSelected {
                            Text(L10n.tr("ACTIVE"))
                                .font(.system(size: 9, weight: .bold))

                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.green.opacity(0.15)))
                                .foregroundStyle(.green)
                        }
                    }
                    HStack(spacing: 12) {
                        Label(model.size, systemImage: "internaldrive")
                        Label(model.speed, systemImage: "bolt.fill")
                        Label(model.accuracy, systemImage: "target")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if isDownloaded {
                    if !isSelected {
                        Button(L10n.tr("Activate")) {
                            settings.selectedModel = model.settingsId
                            engine.reloadModel()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.blue)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 18))
                    }
                } else if modelManager.isDownloading(model) {
                    downloadingControls(for: model)
                } else {
                    Button(L10n.tr("Download")) {
                        modelManager.startDownload(model)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    /// Progress bar + cancel affordance for a model that is actively downloading.
    @ViewBuilder
    private func downloadingControls(for model: ModelManager.ModelInfo) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: modelManager.downloadProgress(for: model) ?? 0)
                .frame(width: 60)
            Button {
                modelManager.cancelDownload(name: model.fileName)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel download")
        }
    }

    private func isModelSelected(_ model: ModelManager.ModelInfo) -> Bool {
        settings.selectedModel == model.settingsId
    }

    private func tierGradient(for model: ModelManager.ModelInfo) -> LinearGradient {
        switch model.fileName {
        case let f where f.contains("base"): return LinearGradient(colors: [.green.opacity(0.7), .green.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case let f where f.contains("small"): return LinearGradient(colors: [.blue.opacity(0.7), .blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default: return LinearGradient(colors: [.purple.opacity(0.7), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func tierEmoji(for model: ModelManager.ModelInfo) -> String {
        switch model.fileName {
        case let f where f.contains("base"): return "⚡"
        case let f where f.contains("small"): return "🎯"
        default: return "🧠"
        }
    }
}

// MARK: - Vocabulary Section

private struct VocabularySection: View {
    @ObservedObject var settings: AppSettings
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            // Names & Terms
            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Names & Terms"), subtitle: L10n.tr("Add names of people, places, and terms you use often"))
                CustomTermsEditor(settings: settings, colorScheme: colorScheme)
            }

            // Developer Vocabulary
            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Developer Vocabulary"), subtitle: L10n.tr("Bias Whisper toward recognizing these terms"))
                TextEditor(text: $settings.vocabularyPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .frame(minHeight: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color(.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 0.5)
                    )

                HStack {
                    Text(L10n.tr("Add project-specific terms for better recognition"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button(L10n.tr("Reset")) {
                        settings.vocabularyPrompt = AppSettings.defaultVocabularyPrompt
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Custom Terms Editor

private struct CustomTermsEditor: View {
    @ObservedObject var settings: AppSettings
    let colorScheme: ColorScheme
    @State private var newTerm = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Input row
            HStack(spacing: 8) {
                TextField(L10n.tr("Type a name or term..."), text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { addTerm() }

                Button(L10n.tr("Add")) { addTerm() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.blue)
                    .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || settings.customTerms.count >= 100)
            }

            // Pills
            if !settings.customTerms.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(settings.customTerms, id: \.self) { term in
                        TermPill(term: term, colorScheme: colorScheme) {
                            settings.removeCustomTerm(term)
                        }
                    }
                }

                HStack {
                    let count = settings.customTerms.count
                    Text("\(count) / 100 terms")
                        .font(.system(size: 11))
                        .foregroundColor(count >= 100 ? .orange : .secondary.opacity(0.5))
                    Spacer()
                    Button(L10n.tr("Clear All")) {
                        settings.customTerms = []
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func addTerm() {
        settings.addCustomTerm(newTerm)
        newTerm = ""
    }
}

// MARK: - Term Pill

private struct TermPill: View {
    let term: String
    let colorScheme: ColorScheme
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(term)
                .font(.system(size: 11, weight: .medium))
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
        .overlay(
            Capsule()
                .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.5)
        )
    }
}



// MARK: - Permissions Section

private struct PermissionsSection: View {
    @ObservedObject var permissions: PermissionManager
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 14) {
            PermissionCard(
                icon: "mic.fill",
                title: "Microphone",
                description: "Capture your voice for transcription",
                isGranted: permissions.microphoneGranted,
                colorScheme: colorScheme,
                action: { permissions.requestMicrophone() },
                actionLabel: "Grant Access"
            )

            PermissionCard(
                icon: "hand.raised.fill",
                title: "Accessibility",
                description: "Global hotkey and text injection at cursor",
                isGranted: permissions.accessibilityGranted,
                colorScheme: colorScheme,
                action: { permissions.openAccessibilitySettings() },
                actionLabel: "Open Settings"
            )

            Button {
                permissions.checkPermissions()
            } label: {
                Label("Refresh Permissions", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let colorScheme: ColorScheme
    let action: () -> Void
    let actionLabel: String

    var body: some View {
        SettingsCard(colorScheme: colorScheme) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isGranted
                            ? LinearGradient(colors: [.green.opacity(0.7), .green.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.red.opacity(0.7), .red.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: isGranted ? "checkmark" : icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isGranted {
                    Button(actionLabel, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.blue)
                }
            }
        }
    }
}
