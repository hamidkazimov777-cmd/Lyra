import SwiftUI

struct SpeechSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var modelManager: ModelManager
    let engine: DictationEngine
    let colorScheme: ColorScheme

    @State private var isFetchingModels = false
    @State private var fetchModelsError: String?
    @State private var isTestingModel = false
    @State private var testModelResult: (success: Bool, message: String, sampleOutput: String?, latencyMs: Int)?

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

                Divider()
                    .padding(.vertical, 4)

                CardHeader(L10n.tr("Language"), subtitle: L10n.tr("Dictation language and matching Whisper models"))
                Picker(L10n.tr("Dictation Language"), selection: languageBinding) {
                    ForEach(Language.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .font(.system(size: 13))

                Text(L10n.tr("English-only models are hidden when a multilingual language is selected, and vice versa."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Transcription & Smart Voice Features"), subtitle: L10n.tr("Live streaming and intelligent voice manipulation"))
                Toggle(L10n.tr("Auto-correct grammar & formatting"), isOn: $settings.grammarCorrectionEnabled)
                    .font(.system(size: 13))
                Toggle(L10n.tr("Convert number words to digits"), isOn: $settings.numberConversionEnabled)
                    .font(.system(size: 13))
                Divider()
                Toggle(L10n.tr("Smart Voice Editing (Transform Selected Text)"), isOn: $settings.smartVoiceEditingEnabled)
                    .font(.system(size: 13))
                Text(L10n.tr("When text is highlighted in any app, dictation acts as a voice command (rewrite, translate, edit) applied directly to your selection."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("AI Text Post-Processing"), subtitle: L10n.tr("Refines dictation using an LLM via OpenRouter"))
                Toggle(L10n.tr("Enable AI Post-Processing"), isOn: $settings.aiPostProcessingEnabled)
                    .font(.system(size: 13))

                if settings.aiPostProcessingEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        // 1. Fast Popular Presets
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.tr("Popular Fast Models"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(AppSettings.popularPostProcessingPresets) { preset in
                                        Button {
                                            settings.aiPostProcessingModel = preset.id
                                            testModelResult = nil
                                        } label: {
                                            Text(preset.displayName)
                                                .font(.system(size: 11, weight: settings.aiPostProcessingModel == preset.id ? .semibold : .regular))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    settings.aiPostProcessingModel == preset.id
                                                        ? Color.blue.opacity(0.2)
                                                        : Color.primary.opacity(0.06)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(
                                                            settings.aiPostProcessingModel == preset.id ? Color.blue : Color.clear,
                                                            lineWidth: 1
                                                        )
                                                )
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        // 2. OpenRouter Model Selection & Fetch
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Model Identifier")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    fetchPostProcessingModels()
                                } label: {
                                    HStack(spacing: 4) {
                                        if isFetchingModels {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                                .frame(width: 12, height: 12)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        Text("Fetch Models")
                                    }
                                    .font(.system(size: 11))
                                }
                                .buttonStyle(.borderless)
                                .disabled(isFetchingModels)
                            }

                            if !settings.aiPostProcessingAvailableModels.isEmpty {
                                Picker("Select from OpenRouter", selection: Binding(
                                    get: { settings.aiPostProcessingModel },
                                    set: { newModel in
                                        settings.aiPostProcessingModel = newModel
                                        testModelResult = nil
                                    }
                                )) {
                                    ForEach(settings.aiPostProcessingAvailableModels, id: \.self) { modelId in
                                        Text(modelId).tag(modelId)
                                    }
                                }
                                .pickerStyle(.menu)
                                .font(.system(size: 12))
                            }

                            TextField("e.g. google/gemini-3.5-flash-lite", text: $settings.aiPostProcessingModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))

                            if let err = fetchModelsError {
                                Text(err)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            } else if !settings.aiPostProcessingAvailableModels.isEmpty {
                                Text("\(settings.aiPostProcessingAvailableModels.count) models available on OpenRouter")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // 3. Timeout Configuration
                        HStack {
                            Text("Timeout Limit")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("Timeout", selection: $settings.aiPostProcessingTimeoutSeconds) {
                                Text("3.0s (Fast)").tag(3.0)
                                Text("5.0s (Recommended)").tag(5.0)
                                Text("8.0s (Relaxed)").tag(8.0)
                                Text("12.0s (Slow / Thinking)").tag(12.0)
                            }
                            .pickerStyle(.menu)
                            .font(.system(size: 11))
                        }

                        Divider().padding(.vertical, 2)

                        // 4. Test Model Button & Status Feedback
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button {
                                    testSelectedModel()
                                } label: {
                                    HStack(spacing: 6) {
                                        if isTestingModel {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                                .frame(width: 12, height: 12)
                                            Text(L10n.tr("Testing..."))
                                        } else {
                                            Image(systemName: "bolt.badge.checkmark.fill")
                                            Text(L10n.tr("Test Connection"))
                                        }
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isTestingModel || settings.aiPostProcessingModel.isEmpty)

                                Spacer()
                            }

                            if let res = testModelResult {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: res.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .foregroundStyle(res.success ? .green : .red)
                                            .font(.system(size: 12))
                                        Text(res.message)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(res.success ? Color.primary : Color.red)
                                    }
                                    if let sample = res.sampleOutput {
                                        Text("Result: \"\(sample)\"")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .padding(6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.primary.opacity(0.04))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                .padding(8)
                                .background(res.success ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        Text("Fixes punctuation, letter casing, and speech errors while preserving meaning and language. If OpenRouter takes longer than timeout or fails, Lyra automatically uses the Whisper draft.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Live Dictation"), subtitle: L10n.tr("Type each phrase when you pause"))
                Toggle(L10n.tr("Live dictation"), isOn: Binding(
                    get: { settings.liveDictationEnabled },
                    set: { enabled in
                        settings.liveDictationEnabled = enabled
                        if enabled
                            && !modelManager.isModelDownloaded(ModelManager.ModelInfo.vadSilero)
                            && !modelManager.isDownloading(.vadSilero) {
                            modelManager.startDownload(.vadSilero)
                        }
                    }
                ))
                .font(.system(size: 13))
                Text(liveDictationCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if settings.aiPostProcessingAvailableModels.isEmpty {
                fetchPostProcessingModels()
            }
        }
    }

    private func fetchPostProcessingModels() {
        isFetchingModels = true
        fetchModelsError = nil

        Task {
            let res = await TranscriptionCoordinator.shared.apiService.fetchPostProcessingModels(
                apiKey: settings.apiKey
            )
            await MainActor.run {
                self.isFetchingModels = false
                if res.success {
                    self.settings.aiPostProcessingAvailableModels = res.models
                } else {
                    self.fetchModelsError = res.message
                }
            }
        }
    }

    private func testSelectedModel() {
        isTestingModel = true
        testModelResult = nil

        Task {
            let res = await TranscriptionCoordinator.shared.apiService.testPostProcessing(
                model: settings.aiPostProcessingModel,
                apiKey: settings.apiKey
            )
            await MainActor.run {
                self.isTestingModel = false
                self.testModelResult = res
            }
        }
    }

    private var languageBinding: Binding<Language> {
        Binding(
            get: { settings.selectedLanguage },
            set: { newLanguage in
                let available = LanguageCatalog.models(for: newLanguage)
                let currentIsAvailable = available.contains { $0.settingsId == settings.selectedModel }
                if !currentIsAvailable {
                    settings.selectedModel = LanguageCatalog.defaultModel(for: newLanguage).settingsId
                    engine.reloadModel()
                }
                settings.selectedLanguage = newLanguage
                // Auto-start the recommended model download for the new language
                // if no compatible model is on disk yet.
                ModelManager.shared.ensureDownloadedRecommendedModel(for: newLanguage)
            }
        )
    }

    private var liveDictationCaption: String {
        guard settings.liveDictationEnabled else {
            return "Types each phrase when you pause, instead of everything at the end. Works best with small or base models."
        }
        if modelManager.isModelDownloaded(ModelManager.ModelInfo.vadSilero) {
            return "Types each phrase when you pause. Works best with small or base models."
        }
        if modelManager.isDownloading(.vadSilero) {
            return "Downloading the voice-activity model — live dictation starts working when it finishes."
        }
        if modelManager.downloadError != nil {
            return "A model download failed — retry from the Models section. Live dictation stays off until the voice-activity model is downloaded."
        }
        return "Requires the voice-activity model (Models section). Live dictation is off until it's downloaded."
    }
}
