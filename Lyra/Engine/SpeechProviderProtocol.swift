import Foundation

/// Defines available transcription provider modes.
enum TranscriptionProviderType: String, CaseIterable, Identifiable {
    case api = "API Provider"
    case local = "Local Whisper"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .api: return "Cloud / Custom API"
        case .local: return "Local Whisper (Offline)"
        }
    }
}

/// Supported popular preset providers to automatically populate Base URL and default models.
///
/// Only providers that actually expose an OpenAI-compatible `/audio/transcriptions`
/// endpoint belong here. Text-only providers (DeepSeek, for example) live in
/// `AppSettings.popularPostProcessingPresets` instead — offering them for speech
/// recognition guarantees a 404.
enum APIPresetProvider: String, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case groq = "Groq"
    case openRouter = "OpenRouter"
    case gemini = "Google Gemini"
    case localGateway = "Local Gateway (Ollama / vLLM)"
    case custom = "Custom"

    var id: String { rawValue }

    var defaultBaseURL: String {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1"
        case .groq:
            return "https://api.groq.com/openai/v1"
        case .openRouter:
            return "https://openrouter.ai/api/v1"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .localGateway:
            return "http://localhost:11434/v1"
        case .custom:
            return "https://api.openai.com/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:
            return "whisper-1"
        case .groq:
            return "whisper-large-v3"
        case .openRouter:
            return "openai/whisper-large-v3"
        case .gemini:
            return "gemini-1.5-flash"
        case .localGateway:
            return "whisper"
        case .custom:
            return "whisper-1"
        }
    }
}

/// Unified error types for transcription operations across providers.
enum TranscriptionServiceError: LocalizedError {
    case invalidURL
    case missingAPIKey
    case networkError(String)
    case serverError(statusCode: Int, message: String)
    case decodingError(String)
    case localModelNotLoaded
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API Base URL."
        case .missingAPIKey:
            return "API Key is required. Please set it in Settings → Provider."
        case .networkError(let details):
            return "Network connection failed: \(details)"
        case .serverError(let code, let msg):
            return "API Server returned status \(code): \(msg)"
        case .decodingError(let msg):
            return "Failed to parse API response: \(msg)"
        case .localModelNotLoaded:
            return "Local Whisper model is not loaded."
        case .cancelled:
            return "Transcription was cancelled."
        case .unknown(let details):
            return "Transcription error: \(details)"
        }
    }

    var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

/// Thread-safe cancellation signal shared across providers.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
}


/// Unified protocol for any speech-to-text service (cloud API, local whisper, etc.).
protocol SpeechTranscriptionProvider: AnyObject, Sendable {
    var providerName: String { get }

    func transcribe(
        samples: [Float],
        language: Language,
        prompt: String,
        cancelFlag: CancellationFlag?
    ) async throws -> String
}
