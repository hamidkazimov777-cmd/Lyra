import Foundation
import Speech
import AVFoundation

/// Lightweight, on-device streaming speech recognizer using Apple's Speech.framework.
/// Provides real-time partial transcriptions for live visual feedback in the Dynamic Island
/// with zero network overhead and zero latency.
final class LiveSpeechRecognizer: @unchecked Sendable {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var isRunning = false

    init() {
        // Completely lazy — do not touch Speech.framework on launch
    }

    func refreshRecognizer(language: Language) {
        let locale = Locale(identifier: language.whisperCode == "ru" ? "ru-RU" : (language.whisperCode == "en" ? "en-US" : language.whisperCode))
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    /// Starts streaming speech recognition on-device if authorized.
    func start(
        language: Language,
        onPartialResult: @escaping (String) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        stop()

        guard SFSpeechRecognizer.authorizationStatus() != .denied &&
              SFSpeechRecognizer.authorizationStatus() != .restricted else {
            return
        }

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in }
        }

        refreshRecognizer(language: language)

        guard let recognizer = self.recognizer, recognizer.isAvailable else {
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            // Prefer on-device transcription for zero latency and privacy if supported
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
        }

        self.recognitionRequest = request
        self.isRunning = true

        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, self.isRunning else { return }

            if let result = result {
                let transcription = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !transcription.isEmpty {
                    DispatchQueue.main.async {
                        onPartialResult(transcription)
                    }
                }
            }
        }
    }

    /// Appends incoming audio PCM buffer from the microphone.
    func append(buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning, let request = recognitionRequest else { return }
        request.append(buffer)
    }

    /// Stops the live streaming session.
    func stop() {
        lock.lock()
        defer { lock.unlock() }

        isRunning = false
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }
}
