import Foundation

/// Robust OpenAI-compatible Audio Transcriptions API client.
/// Works with OpenAI, Groq, OpenRouter, Google Gemini, and local servers (Ollama, vLLM, Whisper HTTP).
final class OpenAISpeechService: SpeechTranscriptionProvider, @unchecked Sendable {
    let providerName: String = "API"

    private let urlSession: URLSession

    init(session: URLSession = .shared) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25.0
        config.timeoutIntervalForResource = 45.0
        self.urlSession = URLSession(configuration: config)
    }

    /// Performs speech transcription via standard POST /audio/transcriptions endpoint.
    func transcribe(
        samples: [Float],
        language: Language,
        prompt: String,
        cancelFlag: CancellationFlag?
    ) async throws -> String {
        if cancelFlag?.isCancelled == true {
            throw TranscriptionServiceError.cancelled
        }

        let settings = AppSettings.shared
        let rawBaseURL = settings.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawBaseURL.isEmpty, let baseURL = URL(string: rawBaseURL) else {
            throw TranscriptionServiceError.invalidURL
        }

        // Construct standard endpoint URL
        let endpointURL: URL
        if rawBaseURL.hasSuffix("/audio/transcriptions") {
            endpointURL = baseURL
        } else if rawBaseURL.hasSuffix("/") {
            endpointURL = URL(string: "audio/transcriptions", relativeTo: baseURL) ?? baseURL.appendingPathComponent("audio/transcriptions")
        } else {
            endpointURL = URL(string: "\(rawBaseURL)/audio/transcriptions") ?? baseURL.appendingPathComponent("audio/transcriptions")
        }

        let model = settings.apiModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "whisper-1"
            : settings.apiModelName.trimmingCharacters(in: .whitespacesAndNewlines)

        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Convert Float32 audio samples to valid 16-bit PCM WAV
        let wavData = WAVEncoder.encodeToWAV(samples: samples)
        guard !wavData.isEmpty else {
            throw TranscriptionServiceError.unknown("Audio buffer was empty.")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if rawBaseURL.contains("openrouter.ai") {
            request.setValue("https://lyra.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Lyra Speech Dictation", forHTTPHeaderField: "X-Title")
        }

        // Build multipart body
        var body = Data()

        // 1. File part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        // 2. Model part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // 3. Language part
        let langCode = language.whisperCode
        if !langCode.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(langCode)\r\n".data(using: .utf8)!)
        }

        // 4. Prompt part (Vocabulary bias)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(trimmedPrompt)\r\n".data(using: .utf8)!)
        }

        // 5. Response format: JSON
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)

        // Final boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        if cancelFlag?.isCancelled == true {
            throw TranscriptionServiceError.cancelled
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            if cancelFlag?.isCancelled == true {
                throw TranscriptionServiceError.cancelled
            }
            throw TranscriptionServiceError.networkError(error.localizedDescription)
        }

        if cancelFlag?.isCancelled == true {
            throw TranscriptionServiceError.cancelled
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionServiceError.networkError("Invalid server response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionServiceError.serverError(statusCode: httpResponse.statusCode, message: errorText)
        }

        // Parse transcription JSON: {"text": "..."}
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let rawString = String(data: data, encoding: .utf8) {
                return rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                throw TranscriptionServiceError.decodingError("Missing 'text' field in response.")
            }
        } catch {
            throw TranscriptionServiceError.decodingError(error.localizedDescription)
        }
    }

    /// Tests API endpoint connectivity by sending a small dummy audio sample.
    func testConnection(
        baseURLString: String,
        apiKey: String,
        modelName: String
    ) async -> (success: Bool, message: String, latencyMs: Int) {
        let startTime = CFAbsoluteTimeGetCurrent()

        let trimmedBase = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, let baseURL = URL(string: trimmedBase) else {
            return (false, "Invalid Base URL format", 0)
        }

        let endpointURL: URL
        if trimmedBase.hasSuffix("/audio/transcriptions") {
            endpointURL = baseURL
        } else if trimmedBase.hasSuffix("/") {
            endpointURL = URL(string: "audio/transcriptions", relativeTo: baseURL) ?? baseURL.appendingPathComponent("audio/transcriptions")
        } else {
            endpointURL = URL(string: "\(trimmedBase)/audio/transcriptions") ?? baseURL.appendingPathComponent("audio/transcriptions")
        }

        let model = modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "whisper-1" : modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // 0.25s of silence (4000 samples @ 16kHz)
        let dummySamples = [Float](repeating: 0.0, count: 4000)
        let wavData = WAVEncoder.encodeToWAV(samples: dummySamples)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        if trimmedBase.contains("openrouter.ai") {
            request.setValue("https://lyra.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Lyra Speech Dictation", forHTTPHeaderField: "X-Title")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"test.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await urlSession.data(for: request)
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "Invalid HTTP response from server", elapsed)
            }

            if (200...299).contains(httpResponse.statusCode) {
                return (true, "Connected successfully (\(elapsed) ms)", elapsed)
            } else if httpResponse.statusCode == 404 {
                // If audio transcription is 404, check if /models works (text-only LLM provider like DeepSeek)
                let modelsCheck = await fetchAvailableModels(baseURLString: baseURLString, apiKey: apiKey)
                if modelsCheck.success {
                    return (false, "Connected to API, but this provider only offers text LLMs and does not support speech-to-text (/audio/transcriptions).", elapsed)
                }
                return (false, "HTTP 404: Endpoint not found (/audio/transcriptions)", elapsed)
            } else {
                let errString = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                let shortError = errString.prefix(120)
                return (false, "HTTP \(httpResponse.statusCode): \(shortError)", elapsed)
            }
        } catch {
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            return (false, "Connection error: \(error.localizedDescription)", elapsed)
        }
    }

    /// Fetches available models from the /models endpoint of any OpenAI-compatible provider.
    func fetchAvailableModels(
        baseURLString: String,
        apiKey: String
    ) async -> (success: Bool, models: [String], message: String) {
        let trimmedBase = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, let baseURL = URL(string: trimmedBase) else {
            return (false, [], "Invalid Base URL")
        }

        let modelsURL: URL
        if trimmedBase.hasSuffix("/models") {
            modelsURL = baseURL
        } else if trimmedBase.hasSuffix("/audio/transcriptions") {
            let parent = baseURL.deletingLastPathComponent()
            modelsURL = parent.appendingPathComponent("models")
        } else if trimmedBase.hasSuffix("/") {
            modelsURL = URL(string: "models", relativeTo: baseURL) ?? baseURL.appendingPathComponent("models")
        } else {
            modelsURL = URL(string: "\(trimmedBase)/models") ?? baseURL.appendingPathComponent("models")
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        if trimmedBase.contains("openrouter.ai") {
            request.setValue("https://lyra.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Lyra Speech Dictation", forHTTPHeaderField: "X-Title")
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, [], "Invalid server response")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let err = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                return (false, [], "Server error \(httpResponse.statusCode): \(err.prefix(80))")
            }

            struct ModelItem: Decodable {
                let id: String
            }
            struct ModelsResponse: Decodable {
                let data: [ModelItem]?
            }

            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            guard let list = decoded.data, !list.isEmpty else {
                return (false, [], "No models returned by API")
            }

            var modelIds = list.map { $0.id }
            modelIds.sort { a, b in
                let aIsAudio = a.lowercased().contains("whisper") || a.lowercased().contains("audio")
                let bIsAudio = b.lowercased().contains("whisper") || b.lowercased().contains("audio")
                if aIsAudio && !bIsAudio { return true }
                if !aIsAudio && bIsAudio { return false }
                return a < b
            }

            return (true, modelIds, "Fetched \(modelIds.count) models")
        } catch {
            return (false, [], error.localizedDescription)
        }
    }

    /// Fetches all models from OpenRouter specifically for AI post-processing,
    /// prioritizing fast reasoning and text generation LLMs (Gemini, GPT, Claude, DeepSeek, Llama).
    func fetchPostProcessingModels(
        apiKey: String? = nil
    ) async -> (success: Bool, models: [String], message: String) {
        let settings = AppSettings.shared
        let key: String
        if let explicitKey = apiKey, !explicitKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            key = explicitKey.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            key = settings.apiKey
        }

        let res = await fetchAvailableModels(baseURLString: "https://openrouter.ai/api/v1/models", apiKey: key)
        guard res.success else { return res }

        var sortedModels = res.models
        sortedModels.sort { a, b in
            let aScore = postProcessingModelScore(a)
            let bScore = postProcessingModelScore(b)
            if aScore != bScore { return aScore > bScore }
            return a < b
        }
        return (true, sortedModels, "Fetched \(sortedModels.count) models")
    }

    private func postProcessingModelScore(_ id: String) -> Int {
        let lower = id.lowercased()
        if lower.contains("gemini-3.5-flash-lite") { return 100 }
        if lower.contains("gemini-3.5") || lower.contains("gemini-2.5") { return 90 }
        if lower.contains("gpt-5.4-nano") { return 85 }
        if lower.contains("gpt-5") || lower.contains("gpt-4o-mini") { return 80 }
        if lower.contains("claude-3.5-haiku") { return 75 }
        if lower.contains("deepseek-chat") || lower.contains("deepseek-v3") { return 70 }
        if lower.contains("flash") || lower.contains("mini") || lower.contains("nano") || lower.contains("haiku") { return 60 }
        if lower.contains("whisper") { return 10 }
        return 50
    }

    /// Result of an AI post-processing attempt including latency and diagnostic error details.
    struct PostProcessResult: Sendable {
        let text: String
        let success: Bool
        let elapsedSeconds: Double
        let errorMessage: String?
    }

    /// Refines draft transcription text with full diagnostic feedback.
    func postProcessDetailed(
        draftText: String,
        model: String = AppSettings.defaultAIPostProcessingModel,
        systemPrompt: String = AppSettings.defaultAIPostProcessingPrompt,
        timeoutSeconds: Double = 5.0
    ) async -> PostProcessResult {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PostProcessResult(text: draftText, success: true, elapsedSeconds: 0, errorMessage: nil)
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let settings = AppSettings.shared
        let apiKey = settings.apiKey

        let endpointURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": trimmed]
            ],
            "temperature": 0.1
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            return PostProcessResult(text: draftText, success: false, elapsedSeconds: 0, errorMessage: "Failed to serialize JSON request")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds + 1.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://lyra.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Lyra Speech Dictation", forHTTPHeaderField: "X-Title")
        request.httpBody = httpBody

        let finalRequest = request
        let session = self.urlSession

        do {
            let result = try await withThrowingTaskGroup(of: PostProcessResult.self) { group in
                // 1. Worker task: calls OpenRouter chat completions
                group.addTask {
                    let (data, response) = try await session.data(for: finalRequest)
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    guard let httpResponse = response as? HTTPURLResponse else {
                        return PostProcessResult(text: trimmed, success: false, elapsedSeconds: elapsed, errorMessage: "Invalid server response")
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        var message = "HTTP \(httpResponse.statusCode)"
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errObj = json["error"] as? [String: Any],
                           let errMsg = errObj["message"] as? String {
                            message = "HTTP \(httpResponse.statusCode): \(errMsg)"
                        } else if let rawErr = String(data: data, encoding: .utf8) {
                            message = "HTTP \(httpResponse.statusCode): \(rawErr.prefix(80))"
                        }
                        fputs("[OpenAISpeechService] Post-processing error: \(message)\n", stderr)
                        return PostProcessResult(text: trimmed, success: false, elapsedSeconds: elapsed, errorMessage: message)
                    }

                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let first = choices.first,
                       let message = first["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalText = cleaned.isEmpty ? trimmed : cleaned
                        return PostProcessResult(text: finalText, success: true, elapsedSeconds: elapsed, errorMessage: nil)
                    }
                    return PostProcessResult(text: trimmed, success: false, elapsedSeconds: elapsed, errorMessage: "Empty response from model")
                }

                // 2. Timeout watchdog task
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    let msg = "Post-processing timed out after \(String(format: "%.1f", timeoutSeconds))s"
                    fputs("[OpenAISpeechService] \(msg)\n", stderr)
                    return PostProcessResult(text: trimmed, success: false, elapsedSeconds: elapsed, errorMessage: msg)
                }

                // First to finish wins!
                guard let firstResult = try await group.next() else {
                    return PostProcessResult(text: trimmed, success: false, elapsedSeconds: CFAbsoluteTimeGetCurrent() - startTime, errorMessage: "Unknown task failure")
                }
                group.cancelAll()
                return firstResult
            }
            return result
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let msg = "Network error: \(error.localizedDescription)"
            fputs("[OpenAISpeechService] \(msg)\n", stderr)
            return PostProcessResult(text: draftText, success: false, elapsedSeconds: elapsed, errorMessage: msg)
        }
    }

    /// Convenience overload returning just refined text.
    func postProcessText(
        draftText: String,
        model: String = AppSettings.defaultAIPostProcessingModel,
        systemPrompt: String = AppSettings.defaultAIPostProcessingPrompt,
        timeoutSeconds: Double = 5.0
    ) async -> String {
        let res = await postProcessDetailed(
            draftText: draftText,
            model: model,
            systemPrompt: systemPrompt,
            timeoutSeconds: timeoutSeconds
        )
        return res.text
    }

    /// Tests the connection and functionality of a chosen post-processing model.
    func testPostProcessing(
        model: String,
        apiKey: String? = nil
    ) async -> (success: Bool, message: String, sampleOutput: String?, latencyMs: Int) {
        let testSample = "Слушай, мне кажется, не работает постобработка диктовки."
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = await postProcessDetailed(
            draftText: testSample,
            model: model,
            systemPrompt: AppSettings.defaultAIPostProcessingPrompt,
            timeoutSeconds: 8.0
        )
        let latency = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        if result.success {
            return (true, "Connected successfully (\(latency) ms)", result.text, latency)
        } else {
            return (false, result.errorMessage ?? "Failed to connect", nil, latency)
        }
    }

    /// Transforms the user's selected text according to their spoken voice instruction.
    func transformSelectedText(
        originalText: String,
        instruction: String,
        model: String = AppSettings.defaultAIPostProcessingModel,
        timeoutSeconds: Double = 8.0
    ) async -> PostProcessResult {
        let trimmedOriginal = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedOriginal.isEmpty else {
            return PostProcessResult(text: instruction, success: true, elapsedSeconds: 0, errorMessage: nil)
        }
        guard !trimmedInstruction.isEmpty else {
            return PostProcessResult(text: originalText, success: true, elapsedSeconds: 0, errorMessage: nil)
        }

        let systemPrompt = """
        Ты — интеллектуальный редактор текста. Твоя задача — изменить исходный выделенный текст пользователя в соответствии с его голосовой инструкцией.

        Правила:
        - Строго и точно примени указания из голосовой инструкции к исходному тексту.
        - Если инструкция просит перевести, переписать, сделать вежливее/официальнее, исправить ошибки, сократить или дополнить — возвращай ТОЛЬКО полученный измененный текст.
        - Если голосовая инструкция представляет собой готовый новый текст для замены — замени исходный текст на него с соблюдением пунктуации.
        - Ни в коем случае не пиши вводных фраз, пояснений, комментариев и не оборачивай текст в кавычки или markdown-блоки, если их не было в исходном тексте.
        - Сохраняй исходный регистр и абзацы, если инструкция не требует иного.
        """

        let userPrompt = """
        <selected_text>
        \(trimmedOriginal)
        </selected_text>

        <voice_instruction>
        \(trimmedInstruction)
        </voice_instruction>
        """

        let startTime = CFAbsoluteTimeGetCurrent()
        let settings = AppSettings.shared
        let apiKey = settings.apiKey

        let endpointURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.2
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            return PostProcessResult(text: originalText, success: false, elapsedSeconds: 0, errorMessage: "Failed to serialize JSON request")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds + 1.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://lyra.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Lyra Speech Dictation", forHTTPHeaderField: "X-Title")
        request.httpBody = httpBody

        let finalRequest = request
        let session = self.urlSession

        do {
            let result = try await withThrowingTaskGroup(of: PostProcessResult.self) { group in
                group.addTask {
                    let (data, response) = try await session.data(for: finalRequest)
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    guard let httpResponse = response as? HTTPURLResponse else {
                        return PostProcessResult(text: originalText, success: false, elapsedSeconds: elapsed, errorMessage: "Invalid server response")
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        var message = "HTTP \(httpResponse.statusCode)"
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errObj = json["error"] as? [String: Any],
                           let errMsg = errObj["message"] as? String {
                            message = "HTTP \(httpResponse.statusCode): \(errMsg)"
                        }
                        fputs("[OpenAISpeechService] Transform error: \(message)\n", stderr)
                        return PostProcessResult(text: originalText, success: false, elapsedSeconds: elapsed, errorMessage: message)
                    }

                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let first = choices.first,
                       let message = first["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalText = cleaned.isEmpty ? originalText : cleaned
                        return PostProcessResult(text: finalText, success: true, elapsedSeconds: elapsed, errorMessage: nil)
                    }
                    return PostProcessResult(text: originalText, success: false, elapsedSeconds: elapsed, errorMessage: "Empty response from model")
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    let msg = "Transform timed out after \(String(format: "%.1f", timeoutSeconds))s"
                    fputs("[OpenAISpeechService] \(msg)\n", stderr)
                    return PostProcessResult(text: originalText, success: false, elapsedSeconds: elapsed, errorMessage: msg)
                }

                guard let firstResult = try await group.next() else {
                    return PostProcessResult(text: originalText, success: false, elapsedSeconds: CFAbsoluteTimeGetCurrent() - startTime, errorMessage: "Task failure")
                }
                group.cancelAll()
                return firstResult
            }
            return result
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let msg = "Network error: \(error.localizedDescription)"
            fputs("[OpenAISpeechService] \(msg)\n", stderr)
            return PostProcessResult(text: originalText, success: false, elapsedSeconds: elapsed, errorMessage: msg)
        }
    }
}

