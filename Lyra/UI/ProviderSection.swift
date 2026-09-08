import SwiftUI

/// Settings section dedicated to speech recognition providers (Cloud API, OpenAI-compatible, and Local Fallback).
struct ProviderSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var coordinator = TranscriptionCoordinator.shared
    @ObservedObject var modelManager = ModelManager.shared
    let engine: DictationEngine
    let colorScheme: ColorScheme

    @State private var isTesting = false
    @State private var testResult: (success: Bool, message: String)?
    @State private var showAPIKey = false
    @State private var showLLMKey = false
    @State private var showDeepgramKey = false
    @State private var isFetchingModels = false
    @State private var fetchModelsError: String?

    var body: some View {
        VStack(spacing: 16) {
            // Main Mode Selection
            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Transcription Mode"), subtitle: L10n.tr("Choose between Cloud/Custom API or 100% offline Local Whisper"))

                Picker("Mode", selection: $settings.transcriptionProviderType) {
                    ForEach(TranscriptionProviderType.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .font(.system(size: 13))

                if settings.transcriptionProviderType == .api {
                    Text(L10n.tr("API mode provides the highest recognition accuracy and speed, especially for Russian and specialized technical vocabulary."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.tr("Local Whisper processes speech entirely on your Mac using your GPU/CPU without sending any data over the internet."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if settings.transcriptionProviderType == .api {
                apiConfigurationCards
            } else {
                localConfigurationCards
            }

            // Fallback Configuration
            fallbackCard
        }
    }

    // MARK: - API Configuration

    private var apiConfigurationCards: some View {
        VStack(spacing: 14) {
            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("Provider Preset"), subtitle: L10n.tr("Select a pre-configured provider or enter custom settings"))

                Picker(L10n.tr("Preset"), selection: Binding(
                    get: { settings.apiPreset },
                    set: { newPreset in
                        settings.apiPreset = newPreset
                        if newPreset != .custom {
                            settings.apiBaseURL = newPreset.defaultBaseURL
                            settings.apiModelName = newPreset.defaultModel
                            fetchModels()
                        }
                    }
                )) {
                    ForEach(APIPresetProvider.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .font(.system(size: 13))
            }

            SettingsCard(colorScheme: colorScheme) {
                CardHeader(L10n.tr("API Connection"), subtitle: L10n.tr("Endpoint and authentication credentials"))

                // Base URL
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Base URL"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("https://api.openai.com/v1", text: $settings.apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

                // API Key
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.tr("API Key"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(showAPIKey ? L10n.tr("Hide") : L10n.tr("Show")) {
                            showAPIKey.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }

                    if showAPIKey {
                        TextField("sk-...", text: $settings.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("sk-...", text: $settings.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Text(L10n.tr("Your key is stored in the macOS Keychain and sent only to the endpoint you configured."))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // Model Selection (with auto-fetched models picker)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.tr("Model Name"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            fetchModels()
                        } label: {
                            HStack(spacing: 4) {
                                if isFetchingModels {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(L10n.tr("Fetch Models"))
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .disabled(isFetchingModels || settings.apiBaseURL.isEmpty)
                    }

                    if !settings.apiAvailableModels.isEmpty {
                        Picker(L10n.tr("Select Model"), selection: $settings.apiModelName) {
                            ForEach(settings.apiAvailableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: 12))
                    }

                    TextField(L10n.tr("Model identifier (e.g. whisper-1)"), text: $settings.apiModelName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    if let err = fetchModelsError {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    } else if !settings.apiAvailableModels.isEmpty {
                        Text("\(settings.apiAvailableModels.count) " + L10n.tr("models available on this API"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                // Test Connection Row
                HStack(spacing: 12) {
                    Button {
                        runConnectionTest()
                    } label: {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                            Text(L10n.tr("Testing..."))
                        } else {
                            Label(L10n.tr("Test Connection"), systemImage: "bolt.horizontal.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.blue)
                    .disabled(isTesting || settings.apiBaseURL.isEmpty)

                    if let result = testResult {
                        HStack(spacing: 6) {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(result.success ? .green : .orange)
                            Text(result.message)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(result.success ? .primary : .secondary)
                                .lineLimit(3)
                        }
                    }

                    Spacer()
                }
            }

            aiProviderCard
            streamingPreviewCard
        }
    }

    // MARK: - Streaming preview provider

    /// Deepgram's streaming API, used only for the live preview in the HUD.
    ///
    /// It exists as a separate provider because an OpenAI-compatible
    /// `/audio/transcriptions` endpoint is request/response and has no partial
    /// results by construction — without a streaming socket the preview can
    /// only ever show finished phrases, never words as they are spoken.
    private var streamingPreviewCard: some View {
        SettingsCard(colorScheme: colorScheme) {
            CardHeader(L10n.tr("Streaming Transcription"), subtitle: L10n.tr("Recommended. Transcribes while you speak, instead of uploading the recording afterwards"))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.tr("Deepgram API Key"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(showDeepgramKey ? L10n.tr("Hide") : L10n.tr("Show")) { showDeepgramKey.toggle() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                }
                if showDeepgramKey {
                    TextField("", text: $settings.deepgramAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                } else {
                    SecureField("", text: $settings.deepgramAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                Text(L10n.tr("Stored in the macOS Keychain and sent only to Deepgram. Leave empty to keep transcribing with the provider above."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("Model"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(DeepgramStreamingClient.defaultModel, text: $settings.deepgramModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Text(L10n.tr("A model whose name contains \"multi\" detects the spoken language itself."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let error = engine.streamingPreviewError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if settings.isDeepgramConfigured {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Text(L10n.tr("Deepgram transcribes your dictation. The provider above stays as an automatic fallback, and AI post-processing still runs on the result."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - AI post-processing / Smart Edit provider

    /// Chat-completions endpoint used by AI post-processing and Smart Voice
    /// Editing. Deliberately independent of the speech endpoint: most speech
    /// providers are not the user's preferred LLM, and prior builds shipped the
    /// speech key to openrouter.ai regardless of who it belonged to.
    private var aiProviderCard: some View {
        SettingsCard(colorScheme: colorScheme) {
            CardHeader(L10n.tr("AI Text Provider"), subtitle: L10n.tr("Endpoint for post-processing and Smart Voice Editing"))

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("Base URL"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(AppSettings.defaultLLMBaseURL, text: $settings.llmBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            Toggle(isOn: $settings.llmUsesSTTCredentials) {
                Text(L10n.tr("Reuse the speech provider's API key"))
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .disabled(!llmSharesHostWithSpeechProvider)

            if !llmSharesHostWithSpeechProvider {
                Text(L10n.tr("Available only when both endpoints use the same host — a key is never sent to a different provider."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.tr("API Key"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(showLLMKey ? L10n.tr("Hide") : L10n.tr("Show")) { showLLMKey.toggle() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                }
                if showLLMKey {
                    TextField("sk-or-...", text: $settings.llmAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                } else {
                    SecureField("sk-or-...", text: $settings.llmAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                Text(L10n.tr("Leave empty for a local gateway that needs no authentication."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var llmSharesHostWithSpeechProvider: Bool {
        guard let llmHost = URL(string: settings.llmBaseURL)?.host?.lowercased(),
              let sttHost = URL(string: settings.apiBaseURL)?.host?.lowercased() else { return false }
        return llmHost == sttHost
    }

    // MARK: - Local Configuration

    private var localConfigurationCards: some View {
        SettingsCard(colorScheme: colorScheme) {
            CardHeader(L10n.tr("Local Model Status"), subtitle: L10n.tr("Active on-device Whisper model"))

            HStack(spacing: 10) {
                Circle()
                    .fill(engine.isModelLoaded ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.isModelLoaded ? L10n.tr("Local Engine Ready") : L10n.tr("Loading Model..."))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.tr("Active:") + " \(settings.selectedModel)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !engine.isModelLoaded {
                    Button(L10n.tr("Reload")) {
                        engine.reloadModel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Fallback Card

    private var fallbackCard: some View {
        SettingsCard(colorScheme: colorScheme) {
            CardHeader(L10n.tr("Offline Fallback"), subtitle: L10n.tr("Use Local Whisper if API is unavailable"))

            Toggle(L10n.tr("Offline Fallback"), isOn: $settings.enableLocalFallback)
                .font(.system(size: 13))

            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                Text(L10n.tr("Automatically falls back to local Whisper models if network is down or API returns an error."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fetchModels() {
        guard !settings.apiBaseURL.isEmpty else { return }
        isFetchingModels = true
        fetchModelsError = nil

        Task {
            let res = await coordinator.apiService.fetchAvailableModels(
                baseURLString: settings.apiBaseURL,
                apiKey: settings.apiKey
            )
            await MainActor.run {
                self.isFetchingModels = false
                if res.success {
                    self.settings.apiAvailableModels = res.models
                    if !res.models.isEmpty && !res.models.contains(self.settings.apiModelName) {
                        if let first = res.models.first {
                            self.settings.apiModelName = first
                        }
                    }
                } else {
                    self.fetchModelsError = res.message
                }
            }
        }
    }

    private func runConnectionTest() {
        isTesting = true
        testResult = nil

        Task {
            async let testTask = coordinator.apiService.testConnection(
                baseURLString: settings.apiBaseURL,
                apiKey: settings.apiKey,
                modelName: settings.apiModelName
            )
            async let modelsTask = coordinator.apiService.fetchAvailableModels(
                baseURLString: settings.apiBaseURL,
                apiKey: settings.apiKey
            )

            let res = await testTask
            let modelsRes = await modelsTask

            await MainActor.run {
                self.isTesting = false
                self.testResult = (res.success, res.message)
                if modelsRes.success {
                    self.settings.apiAvailableModels = modelsRes.models
                }
            }
        }
    }
}
