import Foundation

final class AppSettings: ObservableObject, @unchecked Sendable {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Hotkey Mode

    enum HotkeyMode: String { case pushToTalk, toggle }

    // MARK: - Text Insertion Method

    enum TextInsertionMethod: String, CaseIterable, Identifiable {
        case paste = "Paste (Cmd+V)"
        case keystrokes = "Simulate Keystrokes"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .paste: return "Clipboard Paste (Cmd+V) — Universal & Fast"
            case .keystrokes: return "Simulate Keystrokes (Typewriter)"
            }
        }
    }

    // MARK: - Keys

    private enum Key: String {
        case hotkeyKeyCode
        case hotkeyModifierFlags
        case handsFreeHotkeyKeyCode
        case handsFreeHotkeyModifierFlags
        case handsFreeTapThreshold
        case hotkeyMode
        case textInsertionMethod
        case selectedModel
        case soundFeedbackEnabled
        case vocabularyPrompt
        case launchAtLogin
        case minimumRecordingDuration
        case grammarCorrectionEnabled
        case selectedAudioDeviceUID
        case numberConversionEnabled
        case customTerms
        case hasCompletedOnboarding
        case liveDictationEnabled
        case showRecordingHUD
        case selectedLanguage
        // API Provider Keys
        case transcriptionProviderType
        case apiPreset
        case apiBaseURL
        case apiKey
        case apiModelName
        case enableLocalFallback
        // LLM (post-processing / Smart Edit) provider keys — independent of STT
        case llmBaseURL
        case llmUsesSTTCredentials
        // Dynamic Island / Floating Widget Keys
        case isFloatingWidgetAlwaysVisible
        case floatingWidgetPositionX
        case floatingWidgetPositionY
        // AI Text Post-Processing Keys
        case aiPostProcessingEnabled
        case aiPostProcessingModel
        case aiPostProcessingAvailableModels
        case aiPostProcessingPrompt
        case aiPostProcessingTimeoutSeconds
        // Smart Voice Editing Keys
        case smartVoiceEditingEnabled
        // Interface Localization Key
        case interfaceLanguage
        // Privacy
        case historyLoggingEnabled
        // Audio
        case fastMicrophoneStartEnabled
        // Live preview in the HUD
        case livePreviewEnabled
        // Deepgram streaming preview
        case deepgramModel
        case deepgramBaseURL
        // One-shot migration marker: secrets moved from UserDefaults to Keychain
        case didMigrateSecretsToKeychain
    }

    // MARK: - Properties

    var hotkeyKeyCode: Int {
        get { defaults.object(forKey: Key.hotkeyKeyCode.rawValue) as? Int ?? 58 } // 58 = Left Option (default per spec)
        set { defaults.set(newValue, forKey: Key.hotkeyKeyCode.rawValue); objectWillChange.send() }
    }

    /// Modifier flags that must accompany `hotkeyKeyCode`, as an
    /// `NSEvent.ModifierFlags`/`CGEventFlags` raw value. Zero means the binding
    /// is a bare key (a lone modifier such as ⌥, or a plain key such as F5).
    var hotkeyModifierFlags: UInt64 {
        get { UInt64(defaults.object(forKey: Key.hotkeyModifierFlags.rawValue) as? UInt ?? 0) }
        set { defaults.set(UInt(newValue), forKey: Key.hotkeyModifierFlags.rawValue); objectWillChange.send() }
    }

    /// Optional second binding that always toggles hands-free dictation,
    /// regardless of the primary key's mode. `-1` means unassigned.
    var handsFreeHotkeyKeyCode: Int {
        get { defaults.object(forKey: Key.handsFreeHotkeyKeyCode.rawValue) as? Int ?? -1 }
        set { defaults.set(newValue, forKey: Key.handsFreeHotkeyKeyCode.rawValue); objectWillChange.send() }
    }

    var handsFreeHotkeyModifierFlags: UInt64 {
        get { UInt64(defaults.object(forKey: Key.handsFreeHotkeyModifierFlags.rawValue) as? UInt ?? 0) }
        set { defaults.set(UInt(newValue), forKey: Key.handsFreeHotkeyModifierFlags.rawValue); objectWillChange.send() }
    }

    var primaryHotkey: HotkeyBinding {
        get { HotkeyBinding(keyCode: hotkeyKeyCode, modifierFlags: hotkeyModifierFlags) }
        set {
            hotkeyKeyCode = newValue.keyCode
            hotkeyModifierFlags = newValue.modifierFlags
        }
    }

    var handsFreeHotkey: HotkeyBinding {
        get { HotkeyBinding(keyCode: handsFreeHotkeyKeyCode, modifierFlags: handsFreeHotkeyModifierFlags) }
        set {
            handsFreeHotkeyKeyCode = newValue.keyCode
            handsFreeHotkeyModifierFlags = newValue.modifierFlags
        }
    }

    /// How long the primary key must be held before releasing it counts as
    /// "push-to-talk stop". A shorter press is a tap, which leaves recording
    /// running hands-free. Replaces a threshold that used to be hardcoded at
    /// 0.35 s in the engine.
    var handsFreeTapThreshold: Double {
        get {
            let stored = defaults.object(forKey: Key.handsFreeTapThreshold.rawValue) as? Double ?? 0.35
            return max(0.15, min(1.0, stored))
        }
        set {
            defaults.set(max(0.15, min(1.0, newValue)), forKey: Key.handsFreeTapThreshold.rawValue)
            objectWillChange.send()
        }
    }

    var hotkeyMode: HotkeyMode {
        get {
            let raw = defaults.string(forKey: Key.hotkeyMode.rawValue) ?? HotkeyMode.pushToTalk.rawValue
            return HotkeyMode(rawValue: raw) ?? .pushToTalk
        }
        set { defaults.set(newValue.rawValue, forKey: Key.hotkeyMode.rawValue); objectWillChange.send() }
    }

    var textInsertionMethod: TextInsertionMethod {
        get {
            guard let raw = defaults.string(forKey: Key.textInsertionMethod.rawValue),
                  let method = TextInsertionMethod(rawValue: raw) else {
                return .paste
            }
            return method
        }
        set { defaults.set(newValue.rawValue, forKey: Key.textInsertionMethod.rawValue); objectWillChange.send() }
    }

    // MARK: - Provider Properties

    var transcriptionProviderType: TranscriptionProviderType {
        get {
            guard let raw = defaults.string(forKey: Key.transcriptionProviderType.rawValue),
                  let type = TranscriptionProviderType(rawValue: raw) else {
                return .api
            }
            return type
        }
        set { defaults.set(newValue.rawValue, forKey: Key.transcriptionProviderType.rawValue); objectWillChange.send() }
    }

    var apiPreset: APIPresetProvider {
        get {
            guard let raw = defaults.string(forKey: Key.apiPreset.rawValue) else {
                return .openAI
            }
            // "DeepSeek" was offered as a speech preset in <=1.2.2 but has no
            // /audio/transcriptions endpoint, so it could only ever 404. Migrate
            // those users (and their dead base URL) onto a working default.
            if raw == "DeepSeek" {
                defaults.set(APIPresetProvider.openAI.rawValue, forKey: Key.apiPreset.rawValue)
                defaults.set(APIPresetProvider.openAI.defaultBaseURL, forKey: Key.apiBaseURL.rawValue)
                defaults.set(APIPresetProvider.openAI.defaultModel, forKey: Key.apiModelName.rawValue)
                return .openAI
            }
            guard let preset = APIPresetProvider(rawValue: raw) else {
                return .openAI
            }
            return preset
        }
        set { defaults.set(newValue.rawValue, forKey: Key.apiPreset.rawValue); objectWillChange.send() }
    }

    var apiBaseURL: String {
        get {
            defaults.string(forKey: Key.apiBaseURL.rawValue) ?? APIPresetProvider.openAI.defaultBaseURL
        }
        set { defaults.set(newValue, forKey: Key.apiBaseURL.rawValue); objectWillChange.send() }
    }

    /// Keychain account names for the app's secrets.
    private enum Secret {
        static let sttAPIKey = "apiKey"
        static let llmAPIKey = "llmAPIKey"
        static let deepgramAPIKey = "deepgramAPIKey"
    }

    // MARK: - Deepgram streaming preview

    /// Key for Deepgram's streaming API. Stored in the Keychain, like every
    /// other secret. Its presence is what enables word-by-word live preview:
    /// an OpenAI-compatible /audio/transcriptions endpoint cannot produce
    /// partial results at all, so without a streaming provider the preview can
    /// only ever show finished phrases.
    var deepgramAPIKey: String {
        get { KeychainStore.get(Secret.deepgramAPIKey) ?? "" }
        set { KeychainStore.set(newValue, for: Secret.deepgramAPIKey); objectWillChange.send() }
    }

    var isDeepgramConfigured: Bool {
        !deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var deepgramModel: String {
        get {
            let stored = defaults.string(forKey: Key.deepgramModel.rawValue) ?? ""
            return stored.isEmpty ? DeepgramStreamingClient.defaultModel : stored
        }
        set { defaults.set(newValue, forKey: Key.deepgramModel.rawValue); objectWillChange.send() }
    }

    var deepgramBaseURL: String {
        get {
            let stored = defaults.string(forKey: Key.deepgramBaseURL.rawValue) ?? ""
            return stored.isEmpty ? DeepgramStreamingClient.defaultBaseURL : stored
        }
        set { defaults.set(newValue, forKey: Key.deepgramBaseURL.rawValue); objectWillChange.send() }
    }

    /// Speech-to-text provider API key. Stored in the Keychain, never in UserDefaults.
    var apiKey: String {
        get { KeychainStore.get(Secret.sttAPIKey) ?? "" }
        set { KeychainStore.set(newValue, for: Secret.sttAPIKey); objectWillChange.send() }
    }

    // MARK: - LLM provider (post-processing + Smart Voice Editing)

    /// Base URL for chat-completions used by AI post-processing and Smart Edit.
    /// Kept separate from the STT endpoint: the two are frequently different
    /// services, and sending the STT key to an unrelated host would leak it.
    var llmBaseURL: String {
        get {
            let stored = defaults.string(forKey: Key.llmBaseURL.rawValue) ?? ""
            return stored.isEmpty ? Self.defaultLLMBaseURL : stored
        }
        set { defaults.set(newValue, forKey: Key.llmBaseURL.rawValue); objectWillChange.send() }
    }

    static let defaultLLMBaseURL = "https://openrouter.ai/api/v1"

    /// When true, the LLM calls reuse the STT provider's key.
    ///
    /// Defaults to ON, because the host check in `effectiveLLMAPIKey` is what
    /// actually prevents a key leaking to a third party: when both endpoints are
    /// the same service, sending the key there is precisely what the user
    /// configured. Defaulting this off silently broke post-processing for every
    /// existing OpenRouter user — the request went out with no Authorization
    /// header at all and fell back to the raw draft.
    var llmUsesSTTCredentials: Bool {
        get { defaults.object(forKey: Key.llmUsesSTTCredentials.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.llmUsesSTTCredentials.rawValue); objectWillChange.send() }
    }

    /// Dedicated LLM provider key. Stored in the Keychain.
    var llmAPIKey: String {
        get { KeychainStore.get(Secret.llmAPIKey) ?? "" }
        set { KeychainStore.set(newValue, for: Secret.llmAPIKey); objectWillChange.send() }
    }

    /// The key actually sent to the LLM endpoint.
    ///
    /// Precedence: an explicit LLM key wins. Otherwise the STT key is reused
    /// only if the user opted in *and* both endpoints share a host; a host
    /// mismatch returns an empty string rather than leaking the STT secret.
    var effectiveLLMAPIKey: String {
        let dedicated = llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dedicated.isEmpty { return dedicated }
        guard llmUsesSTTCredentials else { return "" }
        guard let llmHost = URL(string: llmBaseURL)?.host?.lowercased(),
              let sttHost = URL(string: apiBaseURL)?.host?.lowercased(),
              llmHost == sttHost else {
            return ""
        }
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Full chat-completions endpoint derived from `llmBaseURL`.
    var llmChatCompletionsURL: URL? {
        var raw = llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        guard !raw.isEmpty else { return nil }
        if raw.hasSuffix("/chat/completions") { return URL(string: raw) }
        return URL(string: raw + "/chat/completions")
    }

    /// True when the LLM endpoint is OpenRouter, which wants attribution headers.
    var llmIsOpenRouter: Bool {
        (URL(string: llmBaseURL)?.host?.lowercased() ?? "").contains("openrouter.ai")
    }

    var apiModelName: String {
        get {
            defaults.string(forKey: Key.apiModelName.rawValue) ?? APIPresetProvider.openAI.defaultModel
        }
        set { defaults.set(newValue, forKey: Key.apiModelName.rawValue); objectWillChange.send() }
    }

    var apiAvailableModels: [String] {
        get { defaults.stringArray(forKey: "apiAvailableModels") ?? [] }
        set { defaults.set(newValue, forKey: "apiAvailableModels"); objectWillChange.send() }
    }

    var enableLocalFallback: Bool {
        get {
            defaults.object(forKey: Key.enableLocalFallback.rawValue) as? Bool ?? true
        }
        set { defaults.set(newValue, forKey: Key.enableLocalFallback.rawValue); objectWillChange.send() }
    }

    // MARK: - AI Post-Processing Properties

    var aiPostProcessingEnabled: Bool {
        get { defaults.object(forKey: Key.aiPostProcessingEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.aiPostProcessingEnabled.rawValue); objectWillChange.send() }
    }

    struct PostProcessingModelPreset: Identifiable, Hashable {
        let id: String
        let displayName: String
        let providerTag: String
    }

    static let popularPostProcessingPresets: [PostProcessingModelPreset] = [
        PostProcessingModelPreset(id: "deepseek/deepseek-chat", displayName: "DeepSeek V3 (cheap)", providerTag: "DeepSeek"),
        PostProcessingModelPreset(id: "google/gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash Lite", providerTag: "Google"),
        PostProcessingModelPreset(id: "openai/gpt-4o-mini", displayName: "GPT-4o Mini", providerTag: "OpenAI"),
        PostProcessingModelPreset(id: "anthropic/claude-haiku-4.5", displayName: "Claude Haiku 4.5", providerTag: "Anthropic")
    ]

    // DeepSeek V3: capable Russian post-processing at a fraction of the cost of
    // the frontier minis — the cheapest sensible default for a tight OpenRouter
    // budget.
    static let defaultAIPostProcessingModel = "deepseek/deepseek-chat"

    /// Model slugs that no longer exist (or never did) and must be moved off any
    /// machine that still has them stored, so post-processing keeps working.
    private static let retiredPostProcessingModels: Set<String> = [
        "openai/gpt-5.4-nano",
        "google/gemini-3.5-flash-lite",
    ]

    var aiPostProcessingModel: String {
        get {
            guard let stored = defaults.string(forKey: Key.aiPostProcessingModel.rawValue), !stored.isEmpty else {
                return Self.defaultAIPostProcessingModel
            }
            // Migrate retired/invalid slugs to the current default
            if Self.retiredPostProcessingModels.contains(stored) {
                defaults.set(Self.defaultAIPostProcessingModel, forKey: Key.aiPostProcessingModel.rawValue)
                return Self.defaultAIPostProcessingModel
            }
            // Migrate invalid Claude slug if present
            if stored == "anthropic/claude-3.5-haiku" {
                defaults.set("anthropic/claude-haiku-4.5", forKey: Key.aiPostProcessingModel.rawValue)
                return "anthropic/claude-haiku-4.5"
            }
            return stored
        }
        set { defaults.set(newValue, forKey: Key.aiPostProcessingModel.rawValue); objectWillChange.send() }
    }

    var aiPostProcessingAvailableModels: [String] {
        get { defaults.stringArray(forKey: Key.aiPostProcessingAvailableModels.rawValue) ?? [] }
        set { defaults.set(newValue, forKey: Key.aiPostProcessingAvailableModels.rawValue); objectWillChange.send() }
    }

    var aiPostProcessingModelDisplayName: String {
        let model = aiPostProcessingModel
        if let preset = Self.popularPostProcessingPresets.first(where: { $0.id == model }) {
            return preset.displayName
        }
        let lastComponent = model.components(separatedBy: "/").last ?? model
        return lastComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    static let defaultAIPostProcessingPrompt = """
Ты выполняешь постобработку диктовки.

Задача: превратить сырую расшифровку устной речи в чистый письменный текст, сохранив слова, смысл и стиль автора.

Правила:

- Сохраняй исходный смысл и язык текста.
- Исправляй пунктуацию и регистр букв.
- Исправляй очевидные ошибки распознавания речи.
- Удаляй слова-паразиты и звуки-заполнители: «ну», «вот», «короче», «как бы», «типа», «значит», «в общем», «это самое», «так сказать», «эээ», «ммм». Удаляй их в начале, в середине и в конце предложения. Если такое слово несёт смысл («вот этот файл», «значит, что оно работает»), оставляй его.
- Обрабатывай оговорки и самоисправления: оставляй только финальный вариант, отменённые слова убирай. Маркеры: «ой», «нет», «точнее», «вернее», «то есть», «зачеркни». Пример: «Встретимся в пять... ой нет, в шесть» → «Встретимся в шесть».
- Удаляй случайные повторы слов, возникшие при диктовке.
- Нормализуй общеизвестные названия продуктов, сервисов, технологий и моделей ИИ (например: ChatGPT, OpenRouter, Whisper, GPT-5.4 Nano, Claude, Gemini, DeepSeek, Lyra, Deepgram).
- Не переписывай стиль автора и не улучшай формулировки.
- Не выбрасывай содержательные части текста и не пересказывай его короче. Удаление паразитов, повторов и оговорок сокращением НЕ считается — это твоя работа.
- Не добавляй новую информацию.
- Не меняй факты, числа, даты и имена без высокой уверенности.
- В спорных случаях удаляй только явные паразиты, остальное оставляй как есть.

Возвращай только исправленный текст без комментариев и пояснений.
"""

    var aiPostProcessingPrompt: String {
        get {
            let stored = defaults.string(forKey: Key.aiPostProcessingPrompt.rawValue)
            // Automatically upgrade legacy prompt to the new detailed prompt
            if let stored, !stored.isEmpty, !stored.hasSuffix("Возвращай только исправленный текст.") {
                return stored
            }
            return Self.defaultAIPostProcessingPrompt
        }
        set { defaults.set(newValue, forKey: Key.aiPostProcessingPrompt.rawValue); objectWillChange.send() }
    }

    var aiPostProcessingTimeoutSeconds: Double {
        get {
            let val = defaults.object(forKey: Key.aiPostProcessingTimeoutSeconds.rawValue) as? Double
            if let val, val >= 3.0 {
                return val
            }
            return 5.0
        }
        set { defaults.set(newValue, forKey: Key.aiPostProcessingTimeoutSeconds.rawValue); objectWillChange.send() }
    }

    // MARK: - Audio

    /// Keeps the capture graph prepared between recordings so the microphone
    /// opens instantly instead of after AVAudioEngine's 100-250 ms cold start.
    ///
    /// Off by default: a permanently prepared input graph can keep macOS's
    /// microphone indicator lit while Lyra is idle, which would misrepresent
    /// what the app is doing. Opting in is the user's call.
    var fastMicrophoneStartEnabled: Bool {
        get { defaults.object(forKey: Key.fastMicrophoneStartEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.fastMicrophoneStartEnabled.rawValue); objectWillChange.send() }
    }

    /// Shows what you are saying inside the floating HUD while you speak, using
    /// the local Whisper model as a fast preview. The final text still goes
    /// through whichever provider and post-processing you configured, so the
    /// preview never affects what gets inserted.
    ///
    /// Off by default: it needs both a local Whisper model and the voice-activity
    /// model on disk, which a cloud-only user would otherwise never download.
    var livePreviewEnabled: Bool {
        get { defaults.object(forKey: Key.livePreviewEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.livePreviewEnabled.rawValue); objectWillChange.send() }
    }

    // MARK: - Privacy

    /// When false, transcriptions are never written to `history.json`.
    /// Off-by-default would break the existing History UI, so it defaults to on
    /// and is surfaced as an explicit "Private mode" switch in Advanced settings.
    var historyLoggingEnabled: Bool {
        get { defaults.object(forKey: Key.historyLoggingEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.historyLoggingEnabled.rawValue); objectWillChange.send() }
    }

    // MARK: - Secret migration

    /// Moves API keys written by pre-Keychain builds out of the plaintext
    /// preferences domain and into the Keychain, then removes the originals.
    /// Runs once; safe to call on every launch.
    func migrateSecretsToKeychainIfNeeded() {
        guard !defaults.bool(forKey: Key.didMigrateSecretsToKeychain.rawValue) else { return }
        if let legacy = defaults.string(forKey: Key.apiKey.rawValue), !legacy.isEmpty {
            KeychainStore.set(legacy, for: Secret.sttAPIKey)
        }
        defaults.removeObject(forKey: Key.apiKey.rawValue)
        defaults.set(true, forKey: Key.didMigrateSecretsToKeychain.rawValue)
    }

    // MARK: - Smart Voice Editing Properties

    var smartVoiceEditingEnabled: Bool {
        get { defaults.object(forKey: Key.smartVoiceEditingEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.smartVoiceEditingEnabled.rawValue); objectWillChange.send() }
    }

    // MARK: - Interface Language

    var interfaceLanguage: AppLanguage {
        get { LocalizationService.shared.currentLanguage }
        set {
            LocalizationService.shared.setLanguage(newValue)
            objectWillChange.send()
        }
    }

    // MARK: - Floating Widget Properties

    var isFloatingWidgetAlwaysVisible: Bool {
        get {
            defaults.object(forKey: Key.isFloatingWidgetAlwaysVisible.rawValue) as? Bool ?? true
        }
        set { defaults.set(newValue, forKey: Key.isFloatingWidgetAlwaysVisible.rawValue); objectWillChange.send() }
    }

    var floatingWidgetPositionX: Double? {
        get { defaults.object(forKey: Key.floatingWidgetPositionX.rawValue) as? Double }
        set { defaults.set(newValue, forKey: Key.floatingWidgetPositionX.rawValue); objectWillChange.send() }
    }

    var floatingWidgetPositionY: Double? {
        get { defaults.object(forKey: Key.floatingWidgetPositionY.rawValue) as? Double }
        set { defaults.set(newValue, forKey: Key.floatingWidgetPositionY.rawValue); objectWillChange.send() }
    }


    var selectedModel: String {
        get {
            let fallback = LanguageCatalog.defaultModel(for: selectedLanguage).settingsId
            let stored = defaults.string(forKey: Key.selectedModel.rawValue) ?? fallback
            // Fall back to the default if the stored id doesn't correspond to any
            // catalog model (see ModelInfo.settingsId). Guards against a stale id left
            // behind after the catalog changes.
            let isKnown = ModelManager.ModelInfo.all.contains { $0.settingsId == stored }
            return isKnown ? stored : fallback
        }
        set { defaults.set(newValue, forKey: Key.selectedModel.rawValue); objectWillChange.send() }
    }

    var soundFeedbackEnabled: Bool {
        get { defaults.object(forKey: Key.soundFeedbackEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.soundFeedbackEnabled.rawValue); objectWillChange.send() }
    }

    var vocabularyPrompt: String {
        get {
            defaults.string(forKey: Key.vocabularyPrompt.rawValue) ?? Self.defaultVocabularyPrompt
        }
        set { defaults.set(newValue, forKey: Key.vocabularyPrompt.rawValue); objectWillChange.send() }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin.rawValue) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin.rawValue); objectWillChange.send() }
    }

    /// Whether the user has seen (or been auto-skipped past) first-launch onboarding.
    /// Defaults to false so a fresh install shows the flow once; existing users who
    /// already have a model on disk are marked complete at launch without ever seeing it.
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding.rawValue); objectWillChange.send() }
    }

    var minimumRecordingDuration: Double {
        get {
            let stored = defaults.object(forKey: Key.minimumRecordingDuration.rawValue) as? Double ?? 0.3
            // Clamp on read: a nonsensical raw value must not gate every recording.
            return max(0.0, min(5.0, stored))
        }
        set { defaults.set(newValue, forKey: Key.minimumRecordingDuration.rawValue); objectWillChange.send() }
    }

    var grammarCorrectionEnabled: Bool {
        get { defaults.object(forKey: Key.grammarCorrectionEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.grammarCorrectionEnabled.rawValue); objectWillChange.send() }
    }

    var numberConversionEnabled: Bool {
        get { defaults.object(forKey: Key.numberConversionEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.numberConversionEnabled.rawValue); objectWillChange.send() }
    }

    /// Live dictation (commit-on-pause): type each phrase when the speaker
    /// pauses instead of everything at stop. Default false. Stores intent —
    /// the engine additionally requires the VAD model on disk per session.
    var liveDictationEnabled: Bool {
        get { defaults.bool(forKey: Key.liveDictationEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.liveDictationEnabled.rawValue); objectWillChange.send() }
    }

    /// Show the floating recording HUD while dictating.
    var showRecordingHUD: Bool {
        get { defaults.object(forKey: Key.showRecordingHUD.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showRecordingHUD.rawValue); objectWillChange.send() }
    }

    /// Selected dictation language (ISO code). Default is English.
    var selectedLanguage: Language {
        get {
            let raw = defaults.string(forKey: Key.selectedLanguage.rawValue) ?? Language.english.rawValue
            return Language(rawValue: raw) ?? .english
        }
        set { defaults.set(newValue.rawValue, forKey: Key.selectedLanguage.rawValue); objectWillChange.send() }
    }

    /// Maximum number of custom vocabulary terms. Mirrors the UI cap; enforced here
    /// so no write path (import, programmatic) can exceed the whisper prompt budget.
    static let maxCustomTerms = 100

    var customTerms: [String] {
        get { defaults.stringArray(forKey: Key.customTerms.rawValue) ?? [] }
        set {
            let capped = Array(newValue.prefix(Self.maxCustomTerms))
            defaults.set(capped, forKey: Key.customTerms.rawValue); objectWillChange.send()
        }
    }

    func addCustomTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var terms = customTerms
        // Avoid duplicates (case-insensitive)
        if !terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            terms.append(trimmed)
            customTerms = terms
        }
    }

    func removeCustomTerm(_ term: String) {
        customTerms = customTerms.filter { $0 != term }
    }

    /// nil means "use system default"
    var selectedAudioDeviceUID: String? {
        get { defaults.string(forKey: Key.selectedAudioDeviceUID.rawValue) }
        set { defaults.set(newValue, forKey: Key.selectedAudioDeviceUID.rawValue); objectWillChange.send() }
    }

    // MARK: - Default Vocabulary Prompt

    // ~500 words — under whisper's 1024 token (~750 word) limit
    static let defaultVocabularyPrompt = """
        Technical software engineering discussion. \
        Languages: JavaScript, TypeScript, Python, Swift, SwiftUI, Rust, Go, Golang, \
        Java, Kotlin, C++, C#, F#, Ruby, PHP, Dart, Scala, Haskell, Elixir, Clojure, \
        Zig, Lua, Objective-C, Perl, COBOL, Fortran, Assembly, WASM, WebAssembly. \
        Frameworks: React, Next.js, Vue, Nuxt, Angular, Svelte, SvelteKit, Remix, \
        Astro, Gatsby, Express, Django, Flask, FastAPI, NestJS, Spring Boot, Rails, \
        Laravel, ASP.NET, Gin, Echo, Fiber, Actix, Rocket, Phoenix, Tailwind, \
        Bootstrap, Material UI, Chakra UI, shadcn, Radix, Headless UI, Storybook. \
        Infrastructure: Docker, Kubernetes, AWS, GCP, Azure, Terraform, Ansible, \
        Pulumi, Nginx, Apache, Caddy, Cloudflare, Vercel, Netlify, Heroku, Railway, \
        Fly.io, Render, Lambda, EC2, S3, CloudFront, ECS, EKS, Fargate, RDS, \
        DynamoDB, SQS, SNS, IAM, VPC, Cloud Run, Cloud Functions, BigQuery. \
        Databases: PostgreSQL, MySQL, SQLite, MongoDB, Redis, Elasticsearch, \
        Cassandra, DynamoDB, Firestore, Firebase, Supabase, PlanetScale, Neon, \
        CockroachDB, Prisma, Drizzle, Sequelize, TypeORM, Mongoose, SQLAlchemy, \
        Knex, Kysely, EdgeDB, SurrealDB, Turso, Upstash. \
        APIs: REST, GraphQL, gRPC, WebSocket, tRPC, OpenAPI, Swagger, Postman, \
        JSON, YAML, XML, protobuf, JWT, OAuth, SAML, CORS, CSRF, webhook, \
        endpoint, middleware, rate limiting, pagination, cursor, offset, idempotent. \
        DevOps: Git, GitHub, GitLab, Bitbucket, CI/CD, GitHub Actions, Jenkins, \
        CircleCI, ArgoCD, Helm, kubectl, Prometheus, Grafana, Datadog, Sentry, \
        PagerDuty, container, pod, replica set, deployment, ingress, namespace, \
        artifact, staging, production, canary, blue-green, rollback, hotfix, \
        feature flag, environment variable, secret, load balancer, reverse proxy, \
        API gateway, service mesh, uptime, latency, throughput, SLA, SLO, SLI. \
        Tools: npm, yarn, pnpm, Bun, Deno, Node.js, Webpack, Vite, Rollup, \
        esbuild, SWC, Babel, ESLint, Prettier, Biome, Cargo, pip, Poetry, uv, \
        CocoaPods, Swift Package Manager, Gradle, Maven, homebrew, apt, Turborepo, \
        Nx, Lerna, Changesets, Husky, lint-staged, commitlint. \
        Frontend: tooltip, dropdown, popover, modal, dialog, sidebar, navbar, \
        breadcrumb, carousel, accordion, checkbox, toggle, slider, pagination, \
        skeleton, spinner, toast, snackbar, avatar, badge, chip, tag, tabs, \
        responsive, viewport, breakpoint, flexbox, grid, z-index, opacity, \
        hover, focus, blur, onClick, onChange, onSubmit, useState, useEffect, \
        useRef, useMemo, useCallback, useContext, useReducer, custom hook, \
        SSR, SSG, ISR, hydration, lazy loading, code splitting, tree shaking, \
        bundler, minify, transpile, polyfill, CSS-in-JS, styled-components, \
        SVG, canvas, WebGL, animation, transition, keyframe, media query, \
        accessibility, ARIA, screen reader, semantic HTML, SEO, meta tags, \
        localStorage, sessionStorage, IndexedDB, service worker, PWA, \
        dark mode, light mode, theme, design system, design tokens, Figma. \
        Backend: controller, route, handler, resolver, schema, migration, seed, \
        ORM, query builder, connection pool, transaction, caching, Redis cache, \
        authentication, authorization, session, cookie, token, RBAC, ACL, SSO, MFA, \
        cron job, queue, worker, pub/sub, event-driven, message broker, RabbitMQ, \
        Kafka, NATS, logging, monitoring, tracing, OpenTelemetry, health check, \
        graceful shutdown, retry, circuit breaker, backoff, dead letter queue. \
        Concepts: API, SDK, CLI, IDE, async, await, promise, callback, closure, \
        mutex, semaphore, thread, coroutine, actor, channel, stream, observable, \
        microservice, monolith, serverless, edge function, CDN, \
        HTTP, HTTPS, TCP, UDP, DNS, SSL, TLS, SSH, SMTP, FTP, \
        pull request, merge, rebase, cherry-pick, squash, commit, branch, tag, \
        unit test, integration test, end-to-end test, TDD, BDD, mock, stub, spy, \
        snapshot test, regression, coverage, assertion, fixture, \
        function, class, struct, enum, protocol, interface, component, module, \
        generic, template, trait, mixin, decorator, annotation, abstract, \
        singleton, factory, observer, strategy, adapter, facade, proxy, \
        big O, algorithm, data structure, hash map, linked list, binary tree, \
        recursion, memoization, dynamic programming, sorting, searching. \
        AI: LLM, GPT, Claude, OpenAI, Anthropic, Hugging Face, Ollama, \
        PyTorch, TensorFlow, MLX, ONNX, Whisper, Stable Diffusion, DALL-E, \
        Midjourney, Copilot, RAG, embedding, vector, inference, fine-tuning, \
        tokenizer, attention, transformer, prompt engineering, agent, tool use. \
        Editors: Xcode, VS Code, IntelliJ, Vim, Neovim, Emacs, JetBrains, \
        terminal, shell, bash, zsh, fish, tmux, iTerm, PowerShell, \
        regex, cron, sed, awk, grep, curl, wget, jq, yq.
        """
}
