import Foundation
import AppKit

final class AsyncBox<T>: @unchecked Sendable {
    var value: T?
}

@main
struct TestRunner {
    static var passed = 0
    static var failed = 0

    static let green = "\u{001B}[32m"
    static let red = "\u{001B}[31m"
    static let cyan = "\u{001B}[36m"
    static let bold = "\u{001B}[1m"
    static let reset = "\u{001B}[0m"

    static func assertTest(_ condition: Bool, _ message: String) {
        if condition {
            passed += 1
            print("  \(green)✓\(reset) \(message)")
        } else {
            failed += 1
            print("  \(red)✗ FAILED:\(reset) \(message)")
        }
    }

    static func runSuite(_ name: String, _ tests: () throws -> Void) {
        print("\n\(bold)\(cyan)▶ Testing: \(name)\(reset)")
        do {
            try tests()
        } catch {
            failed += 1
            print("  \(red)✗ SUITE ERROR:\(reset) \(error)")
        }
    }

    static func runAsync<T: Sendable>(_ block: @escaping @Sendable () async -> T) -> T {
        let box = AsyncBox<T>()
        let sema = DispatchSemaphore(value: 0)
        Task {
            box.value = await block()
            sema.signal()
        }
        sema.wait()
        return box.value!
    }

    static func main() {
        // Suite 1: WAVEncoder Tests
        runSuite("WAVEncoder") {
            let emptyWav = WAVEncoder.encodeToWAV(samples: [], sampleRate: 16000)
            assertTest(emptyWav.count == 44, "Empty WAV has exactly 44 bytes (header only)")

            let riff = String(data: emptyWav.subdata(in: 0..<4), encoding: .ascii)
            assertTest(riff == "RIFF", "Header starts with 'RIFF'")

            let wave = String(data: emptyWav.subdata(in: 8..<12), encoding: .ascii)
            assertTest(wave == "WAVE", "Header contains 'WAVE' format marker")

            let fmt = String(data: emptyWav.subdata(in: 12..<16), encoding: .ascii)
            assertTest(fmt == "fmt ", "Header contains 'fmt ' chunk")

            let dataChunk = String(data: emptyWav.subdata(in: 36..<40), encoding: .ascii)
            assertTest(dataChunk == "data", "Header contains 'data' chunk")

            let sampleCount = 16000
            var samples = [Float](repeating: 0, count: sampleCount)
            for i in 0..<sampleCount {
                samples[i] = sin(Float(i) * 2.0 * .pi * 440.0 / 16000.0)
            }

            let wav = WAVEncoder.encodeToWAV(samples: samples, sampleRate: 16000)
            assertTest(wav.count == 44 + sampleCount * 2, "1 second of 16kHz 16-bit mono is 32044 bytes (got \(wav.count))")

            let extremeSamples: [Float] = [-2.5, 3.0, 0.0]
            let extremeWav = WAVEncoder.encodeToWAV(samples: extremeSamples, sampleRate: 16000)
            assertTest(extremeWav.count == 44 + 6, "Clamped samples encoded correctly")
        }

        // Suite 2: LanguageCatalog Tests (Priority #1 Russian)
        runSuite("LanguageCatalog (Russian Priority #1 + Multi-language)") {
            let ruPrompt = Language.russian.defaultPrompt
            assertTest(!ruPrompt.isEmpty, "Russian system prompt is not empty")
            assertTest(ruPrompt.contains("Kubernetes") || ruPrompt.contains("Docker") || ruPrompt.contains("кубернетес"),
                       "Russian prompt includes IT and developer vocabulary")
            assertTest(ruPrompt.contains("знаки препинания") || ruPrompt.contains("пунктуацию") || ruPrompt.contains("запятые") || ruPrompt.contains("точки"),
                       "Russian prompt includes punctuation rules")

            let enPrompt = Language.english.defaultPrompt
            assertTest(!enPrompt.isEmpty, "English prompt configured")

            let trPrompt = Language.turkish.defaultPrompt
            assertTest(!trPrompt.isEmpty && trPrompt.contains("Türkçe"), "Turkish prompt configured")

            let azPrompt = Language.azerbaijani.defaultPrompt
            assertTest(!azPrompt.isEmpty && azPrompt.contains("Azərbaycan"), "Azerbaijani prompt configured")
        }

        // Suite 3: TextCorrector Tests
        runSuite("TextCorrector (Russian & Developer Terms)") {
            let corrector = TextCorrector()

            let input1 = "я настроил api и подключил sql базу через http rest url"
            let output1 = corrector.correct(input1)
            assertTest(output1.contains("API"), "API capitalized correctly: '\(output1)'")
            assertTest(output1.contains("SQL"), "SQL capitalized correctly: '\(output1)'")
            assertTest(output1.contains("HTTP"), "HTTP capitalized correctly: '\(output1)'")
            assertTest(output1.contains("REST"), "REST capitalized correctly: '\(output1)'")
            assertTest(output1.contains("URL"), "URL capitalized correctly: '\(output1)'")

            let input2 = "тестовая строка без заглавной"
            let output2 = corrector.correct(input2)
            assertTest(output2.hasPrefix("Т"), "First character capitalized: '\(output2)'")

            assertTest(corrector.correct("") == "", "Empty string returns empty string")
        }

        // Suite 4: Settings & Presets
        runSuite("Settings & Provider Presets") {
            let settings = AppSettings.shared

            assertTest(settings.hotkeyKeyCode == 58, "Default hotkey is Left Option (code 58, got \(settings.hotkeyKeyCode))")

            let openAIPreset = APIPresetProvider.openAI
            assertTest(openAIPreset.defaultBaseURL == "https://api.openai.com/v1", "OpenAI preset endpoint correct")
            assertTest(openAIPreset.defaultModel == "whisper-1", "OpenAI preset model is whisper-1")

            let groqPreset = APIPresetProvider.groq
            assertTest(groqPreset.defaultBaseURL == "https://api.groq.com/openai/v1", "Groq preset endpoint correct")
            assertTest(groqPreset.defaultModel.contains("whisper-large-v3"), "Groq preset model is whisper-large-v3")

            let openRouterPreset = APIPresetProvider.openRouter
            assertTest(openRouterPreset.defaultBaseURL == "https://openrouter.ai/api/v1", "OpenRouter preset endpoint correct")

            let localGatewayPreset = APIPresetProvider.localGateway
            assertTest(localGatewayPreset.defaultBaseURL.contains("11434"), "Local Gateway endpoint correct")

            // DeepSeek has no /audio/transcriptions endpoint, so it must not be
            // offered as a speech provider — only as a post-processing model.
            assertTest(
                !APIPresetProvider.allCases.contains { $0.rawValue == "DeepSeek" },
                "DeepSeek is not offered as a speech-to-text preset"
            )
            assertTest(
                AppSettings.popularPostProcessingPresets.contains { $0.id == "deepseek/deepseek-chat" },
                "DeepSeek remains available as a post-processing model"
            )
            assertTest(
                APIPresetProvider.allCases.allSatisfy { $0.defaultBaseURL.hasPrefix("http") },
                "Every speech preset has an http(s) base URL"
            )

            assertTest(settings.enableLocalFallback == true || settings.enableLocalFallback == false, "Fallback setting accessible")
        }

        // Suite 5: SpeechProvider & Error Types
        runSuite("SpeechProvider & Error Handling") {
            let networkError = TranscriptionServiceError.networkError("Host unreachable")
            assertTest(!networkError.isCancellation, "Network error is not cancellation")

            let cancelError = TranscriptionServiceError.cancelled
            assertTest(cancelError.isCancellation, "Cancelled is recognized as cancellation")

            let openAIService = OpenAISpeechService()
            assertTest(openAIService.providerName.contains("API"), "Provider name is descriptive")
        }

        // Suite 6: AI Post-Processing & Model Selection
        runSuite("AI Post-Processing & Model Selection") {
            let settings = AppSettings.shared
            assertTest(settings.aiPostProcessingEnabled, "AI post-processing enabled by default")
            assertTest(settings.aiPostProcessingModel == "google/gemini-3.5-flash-lite", "AI post-processing model is google/gemini-3.5-flash-lite (got \(settings.aiPostProcessingModel))")
            assertTest(settings.aiPostProcessingModelDisplayName == "Gemini 3.5 Flash Lite", "Model display name formatted as Gemini 3.5 Flash Lite")

            // Presets and dynamic selection
            assertTest(!AppSettings.popularPostProcessingPresets.isEmpty, "Popular post-processing presets available")
            assertTest(AppSettings.popularPostProcessingPresets.contains(where: { $0.id == "openai/gpt-5.4-nano" }), "Presets include GPT-5.4 Nano")
            assertTest(AppSettings.popularPostProcessingPresets.contains(where: { $0.id == "google/gemini-3.5-flash-lite" }), "Presets include Gemini 3.5 Flash Lite")

            let originalModel = settings.aiPostProcessingModel
            settings.aiPostProcessingModel = "anthropic/claude-haiku-4.5"
            assertTest(settings.aiPostProcessingModelDisplayName == "Claude Haiku 4.5", "Display name updates to Claude Haiku 4.5")
            settings.aiPostProcessingModel = originalModel

            // Available models storage
            settings.aiPostProcessingAvailableModels = ["google/gemini-3.5-flash-lite", "openai/gpt-5.4-nano"]
            assertTest(settings.aiPostProcessingAvailableModels.count == 2, "Available models stored and retrieved")

            // Prompt rules
            assertTest(settings.aiPostProcessingPrompt.contains("Ты выполняешь постобработку диктовки"), "AI post-processing prompt configured correctly")
            assertTest(settings.aiPostProcessingPrompt.contains("Нормализуй общеизвестные названия"), "AI prompt includes normalization rule")
            assertTest(settings.aiPostProcessingPrompt.contains("Возвращай только исправленный текст без комментариев и пояснений"), "AI prompt ends with strict no-comments requirement")
            assertTest(settings.aiPostProcessingTimeoutSeconds == 5.0, "AI post-processing timeout defaults to 5.0s (got \(settings.aiPostProcessingTimeoutSeconds))")

            let openAIService = OpenAISpeechService()
            let emptyProcessed = runAsync {
                await openAIService.postProcessText(draftText: "")
            }
            assertTest(emptyProcessed == "", "Empty text returns empty string immediately")

            let detailedResult = runAsync {
                await openAIService.postProcessDetailed(draftText: "")
            }
            assertTest(detailedResult.success && detailedResult.text == "", "Detailed post-processing handles empty string")
        }

        // Suite 8: Network layer (URLProtocol-mocked — no real requests)
        runSuite("Network Layer (mocked)") {
            let settings = AppSettings.shared

            // Route LLM traffic at a stub host with a dedicated key, so nothing
            // depends on the machine's real configuration.
            let savedLLMBase = settings.llmBaseURL
            let savedLLMKey = settings.llmAPIKey
            let savedSTTBase = settings.apiBaseURL
            let savedSTTKey = settings.apiKey
            let savedReuse = settings.llmUsesSTTCredentials
            defer {
                settings.llmBaseURL = savedLLMBase
                settings.llmAPIKey = savedLLMKey
                settings.apiBaseURL = savedSTTBase
                settings.apiKey = savedSTTKey
                settings.llmUsesSTTCredentials = savedReuse
                MockURLProtocol.reset()
            }

            settings.llmBaseURL = "https://mock.invalid/v1"
            settings.llmAPIKey = "test-llm-key"

            // --- Endpoint derivation ---
            assertTest(
                settings.llmChatCompletionsURL?.absoluteString == "https://mock.invalid/v1/chat/completions",
                "Chat-completions URL is derived from the configured LLM base URL"
            )
            settings.llmBaseURL = "https://mock.invalid/v1/"
            assertTest(
                settings.llmChatCompletionsURL?.absoluteString == "https://mock.invalid/v1/chat/completions",
                "A trailing slash in the base URL does not produce a double slash"
            )
            settings.llmBaseURL = "https://mock.invalid/v1"

            // --- Key isolation ---
            settings.llmAPIKey = ""
            settings.apiKey = "stt-secret"
            settings.apiBaseURL = "https://speech.invalid/v1"
            settings.llmUsesSTTCredentials = true
            assertTest(
                settings.effectiveLLMAPIKey.isEmpty,
                "The speech key is withheld when the AI endpoint is on a different host"
            )
            settings.apiBaseURL = "https://mock.invalid/v1"
            assertTest(
                settings.effectiveLLMAPIKey == "stt-secret",
                "The speech key is reused only when both endpoints share a host"
            )
            settings.llmUsesSTTCredentials = false
            assertTest(
                settings.effectiveLLMAPIKey.isEmpty,
                "Opting out of key reuse sends no key at all"
            )
            settings.llmAPIKey = "test-llm-key"
            assertTest(
                settings.effectiveLLMAPIKey == "test-llm-key",
                "An explicit AI key takes precedence"
            )

            let service = OpenAISpeechService(protocolClasses: [MockURLProtocol.self])

            // --- Happy path ---
            MockURLProtocol.stub(status: 200, body: """
            {"choices":[{"message":{"content":"Corrected text."}}]}
            """)
            let ok = runAsync { await service.postProcessDetailed(draftText: "corected text") }
            assertTest(ok.success, "200 with a well-formed body succeeds")
            assertTest(ok.text == "Corrected text.", "The assistant message content is extracted (got \(ok.text))")
            assertTest(
                MockURLProtocol.lastRequestURL?.absoluteString == "https://mock.invalid/v1/chat/completions",
                "The request goes to the configured endpoint, not a hardcoded one"
            )
            assertTest(
                MockURLProtocol.lastRequestHeaders["Authorization"] == "Bearer test-llm-key",
                "The configured AI key is sent as a bearer token"
            )
            assertTest(
                MockURLProtocol.lastRequestHeaders["HTTP-Referer"] == nil,
                "OpenRouter attribution headers are not sent to non-OpenRouter hosts"
            )

            // --- OpenRouter attribution headers ---
            settings.llmBaseURL = "https://openrouter.ai/api/v1"
            MockURLProtocol.stub(status: 200, body: """
            {"choices":[{"message":{"content":"ok"}}]}
            """)
            _ = runAsync { await service.postProcessDetailed(draftText: "x") }
            assertTest(
                MockURLProtocol.lastRequestHeaders["HTTP-Referer"] != nil,
                "OpenRouter requests carry the attribution headers"
            )
            settings.llmBaseURL = "https://mock.invalid/v1"

            // --- No key: no Authorization header (local gateways reject empty bearers) ---
            settings.llmAPIKey = ""
            MockURLProtocol.stub(status: 200, body: """
            {"choices":[{"message":{"content":"ok"}}]}
            """)
            _ = runAsync { await service.postProcessDetailed(draftText: "x") }
            assertTest(
                MockURLProtocol.lastRequestHeaders["Authorization"] == nil,
                "No Authorization header is sent when no key is configured"
            )
            settings.llmAPIKey = "test-llm-key"

            // --- HTTP error codes all fall back to the raw draft ---
            for status in [401, 404, 429, 500] {
                MockURLProtocol.stub(status: status, body: #"{"error":{"message":"nope"}}"#)
                let res = runAsync { await service.postProcessDetailed(draftText: "raw draft") }
                assertTest(!res.success, "HTTP \(status) is reported as a failure")
                assertTest(res.text == "raw draft", "HTTP \(status) falls back to the raw draft")
                assertTest(res.errorMessage != nil, "HTTP \(status) reports an error message")
            }

            // --- Malformed JSON ---
            MockURLProtocol.stub(status: 200, body: "not json at all")
            let bad = runAsync { await service.postProcessDetailed(draftText: "raw draft") }
            assertTest(!bad.success, "An unparseable body is a failure")
            assertTest(bad.text == "raw draft", "An unparseable body falls back to the raw draft")

            // --- Transport error ---
            MockURLProtocol.stubError(URLError(.notConnectedToInternet))
            let offline = runAsync { await service.postProcessDetailed(draftText: "raw draft") }
            assertTest(!offline.success, "A transport error is a failure")
            assertTest(offline.text == "raw draft", "A transport error falls back to the raw draft")

            // --- Timeout falls back rather than hanging ---
            MockURLProtocol.stub(status: 200, body: """
            {"choices":[{"message":{"content":"too late"}}]}
            """, delay: 1.5)
            let timedOut = runAsync {
                await service.postProcessDetailed(draftText: "raw draft", timeoutSeconds: 0.3)
            }
            assertTest(!timedOut.success, "Exceeding the timeout is a failure")
            assertTest(timedOut.text == "raw draft", "A timeout falls back to the raw draft")

            // --- Smart Edit uses the same routing and fallback ---
            MockURLProtocol.stub(status: 200, body: """
            {"choices":[{"message":{"content":"Rewritten."}}]}
            """)
            let edited = runAsync {
                await service.transformSelectedText(originalText: "old", instruction: "rewrite")
            }
            assertTest(edited.success && edited.text == "Rewritten.", "Smart Edit returns the transformed text")
            assertTest(
                MockURLProtocol.lastRequestURL?.absoluteString == "https://mock.invalid/v1/chat/completions",
                "Smart Edit uses the configured endpoint too"
            )

            MockURLProtocol.stub(status: 401, body: #"{"error":{"message":"bad key"}}"#)
            let editFailed = runAsync {
                await service.transformSelectedText(originalText: "keep me", instruction: "rewrite")
            }
            assertTest(!editFailed.success, "Smart Edit reports API failures")
            assertTest(editFailed.text == "keep me", "Smart Edit preserves the original text on failure")
        }

        // Suite 9: FFT band mapping
        runSuite("FFT Band Mapping") {
            let fftSize = 1024
            let sampleRate: Float = 16000
            let bandCount = 16
            let fft = FFTAnalyzer(size: fftSize)

            /// Index of the band a pure tone at `frequency` must light up, derived
            /// from the same squared bin mapping the analyzer uses.
            func expectedBand(for frequency: Float) -> Int {
                let bin = frequency / (sampleRate / Float(fftSize))
                let t = (bin / Float(fftSize / 2)).squareRoot()
                return min(bandCount - 1, Int(t * Float(bandCount)))
            }

            func tone(_ frequency: Float) -> [Float] {
                (0..<fftSize).map { i in
                    sin(2 * .pi * frequency * Float(i) / sampleRate)
                }
            }

            func peakBand(_ bands: [Float]) -> Int {
                var best = 0
                for i in bands.indices where bands[i] > bands[best] { best = i }
                return best
            }

            // A correct real FFT puts a pure tone's energy in exactly one band.
            // The pre-1.3.0 code fed vDSP_fft_zrip a flat N-length buffer instead
            // of the even/odd split it requires, which smeared tones across the
            // spectrum — these assertions fail against that packing.
            for frequency in [Float(500), 1000, 2000, 3000] {
                let bands = fft.bands(for: tone(frequency), bandCount: bandCount)
                let expected = expectedBand(for: frequency)
                assertTest(
                    peakBand(bands) == expected,
                    "A \(Int(frequency)) Hz tone peaks in band \(expected) (got \(peakBand(bands)))"
                )
            }

            let silence = fft.bands(for: [Float](repeating: 0, count: fftSize), bandCount: bandCount)
            assertTest(silence.allSatisfy { $0 == 0 }, "Silence produces no band energy")

            let loud = fft.bands(for: tone(1000), bandCount: bandCount)
            assertTest(loud.allSatisfy { $0 >= 0 && $0 <= 1 }, "Band values stay normalized to 0...1")
            assertTest(
                fft.bands(for: [Float](repeating: 0, count: 8), bandCount: bandCount).count == bandCount,
                "A wrong-sized input returns a zeroed band array of the right length"
            )
        }

        // Summary
        print("\n" + String(repeating: "=", count: 50))
        print("\(bold)Test Results: \(green)\(passed) passed\(reset), \(failed > 0 ? "\(red)\(failed) failed" : "\(green)0 failed")\(reset)")
        print(String(repeating: "=", count: 50) + "\n")

        if failed > 0 {
            exit(1)
        }
    }
}


// MARK: - Network mocking

/// URLProtocol stub that answers every request from a canned response, so the
/// networking layer can be tested end-to-end without touching the network.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var status = 200
    private static var body = Data()
    private static var error: Error?
    private static var delay: TimeInterval = 0
    private static var _lastRequestURL: URL?
    private static var _lastRequestHeaders: [String: String] = [:]

    static func stub(status: Int, body: String, delay: TimeInterval = 0) {
        lock.lock()
        Self.status = status
        Self.body = Data(body.utf8)
        Self.error = nil
        Self.delay = delay
        lock.unlock()
    }

    static func stubError(_ error: Error) {
        lock.lock()
        Self.error = error
        Self.delay = 0
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        status = 200
        body = Data()
        error = nil
        delay = 0
        _lastRequestURL = nil
        _lastRequestHeaders = [:]
        lock.unlock()
    }

    static var lastRequestURL: URL? {
        lock.lock(); defer { lock.unlock() }
        return _lastRequestURL
    }

    static var lastRequestHeaders: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return _lastRequestHeaders
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._lastRequestURL = request.url
        Self._lastRequestHeaders = request.allHTTPHeaderFields ?? [:]
        let error = Self.error
        let status = Self.status
        let body = Self.body
        let delay = Self.delay
        Self.lock.unlock()

        let deliver = { [weak self] in
            guard let self else { return }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let response = HTTPURLResponse(
                url: self.request.url ?? URL(string: "https://mock.invalid")!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: body)
            self.client?.urlProtocolDidFinishLoading(self)
        }

        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}
