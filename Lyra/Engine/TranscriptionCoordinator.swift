import Foundation
import Combine

/// Coordinates speech-to-text operations between Cloud/Custom API and Local Whisper.
/// Seamlessly activates Local Whisper fallback when the network or API service is unreachable.
final class TranscriptionCoordinator: ObservableObject, @unchecked Sendable {
    static let shared = TranscriptionCoordinator()

    @Published private(set) var lastUsedProvider: String = "Local Whisper"
    @Published private(set) var isFallbackActive: Bool = false
    @Published private(set) var lastError: String?

    let apiService = OpenAISpeechService()

    /// Transcribes the given audio samples based on user settings, executing automatic local fallback if enabled.
    func transcribe(
        samples: [Float],
        language: Language,
        prompt: String,
        cancelFlag: CancellationFlag?,
        localBridge: WhisperBridge?,
        onSegment: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let settings = AppSettings.shared
        let providerType = settings.transcriptionProviderType

        // Reset per-transcription state
        await MainActor.run {
            self.isFallbackActive = false
            self.lastError = nil
        }

        switch providerType {
        case .api:
            do {
                fputs("[TranscriptionCoordinator] Transcribing via API (\(settings.apiModelName))...\n", stderr)
                let text = try await apiService.transcribe(
                    samples: samples,
                    language: language,
                    prompt: prompt,
                    cancelFlag: cancelFlag
                )

                await MainActor.run {
                    self.lastUsedProvider = "API (\(settings.apiModelName))"
                    self.isFallbackActive = false
                }

                // If streaming segment callback was provided, notify it once with the full result
                if let onSegment, !text.isEmpty {
                    onSegment(text)
                }
                return text

            } catch let error as TranscriptionServiceError where error.isCancellation {
                throw error
            } catch {
                fputs("[TranscriptionCoordinator] API transcription failed: \(error.localizedDescription)\n", stderr)

                // Check if local fallback is permitted and available
                if settings.enableLocalFallback, let localBridge {
                    fputs("[TranscriptionCoordinator] -> Seamlessly falling back to Local Whisper.\n", stderr)

                    await MainActor.run {
                        self.isFallbackActive = true
                        self.lastUsedProvider = "Local Whisper (Fallback)"
                        self.lastError = "API offline: switched to local"
                    }

                    let localText = try await localBridge.transcribe(
                        audioBuffer: samples,
                        language: language,
                        prompt: prompt,
                        cancelFlag: cancelFlag,
                        vad: false,
                        onSegment: onSegment
                    )
                    return localText
                } else {
                    await MainActor.run {
                        self.lastError = error.localizedDescription
                    }
                    throw error
                }
            }

        case .local:
            guard let localBridge else {
                throw TranscriptionServiceError.localModelNotLoaded
            }

            await MainActor.run {
                self.lastUsedProvider = "Local Whisper"
                self.isFallbackActive = false
            }

            let text = try await localBridge.transcribe(
                audioBuffer: samples,
                language: language,
                prompt: prompt,
                cancelFlag: cancelFlag,
                vad: false,
                onSegment: onSegment
            )
            return text
        }
    }
}
