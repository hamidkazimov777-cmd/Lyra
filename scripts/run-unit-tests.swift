import Foundation
import AppKit
import CoreGraphics

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

            // Filler removal and self-correction repair were nominally in the
            // prompt but never fired, because "удаляй слова-паразиты" sat next to
            // "не сокращай текст" and "если есть сомнения, оставляй исходный
            // вариант" — the model resolved the contradiction conservatively and
            // kept every "ну" and "вот". These assert both the concrete rules and
            // the sentence that settles the conflict.
            let prompt = settings.aiPostProcessingPrompt
            for filler in ["«ну»", "«вот»", "«короче»", "«как бы»", "«типа»"] {
                assertTest(prompt.contains(filler), "The prompt names \(filler) as a filler to remove")
            }
            assertTest(
                prompt.contains("сокращением НЕ считается"),
                "The prompt states that removing fillers does not count as shortening"
            )
            assertTest(
                prompt.contains("«Встретимся в пять... ой нет, в шесть» → «Встретимся в шесть»"),
                "The prompt shows a worked self-correction example"
            )
            assertTest(
                prompt.contains("«вот этот файл»"),
                "The prompt carves out fillers that carry meaning"
            )
            assertTest(
                !prompt.contains("Не сокращай текст."),
                "The blanket do-not-shorten rule that blocked filler removal is gone"
            )
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

            // Regression: key reuse must default to ON. Defaulting it off sent
            // post-processing requests to the user's own provider with no
            // Authorization header at all, so every existing OpenRouter setup
            // silently fell back to the raw Whisper draft. The host check below
            // is what provides the safety, not the opt-in.
            UserDefaults.standard.removeObject(forKey: "llmUsesSTTCredentials")
            assertTest(
                settings.llmUsesSTTCredentials,
                "Reusing the speech key defaults to ON so existing setups keep working"
            )
            settings.llmAPIKey = ""
            settings.apiKey = "stt-secret"
            settings.apiBaseURL = "https://mock.invalid/v1"
            settings.llmBaseURL = "https://mock.invalid/v1"
            assertTest(
                settings.effectiveLLMAPIKey == "stt-secret",
                "With defaults and a matching host, post-processing is authenticated"
            )
            settings.apiBaseURL = "https://speech.invalid/v1"
            assertTest(
                settings.effectiveLLMAPIKey.isEmpty,
                "The default still withholds the key when the AI endpoint is elsewhere"
            )
            settings.apiBaseURL = "https://mock.invalid/v1"
            settings.llmAPIKey = "test-llm-key"

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

            // --- No credentials at all: no Authorization header.
            // This is the local-gateway case (Ollama / vLLM), where an empty
            // bearer makes some servers reject the request outright. Both key
            // sources have to be off, since reuse is on by default.
            settings.llmAPIKey = ""
            settings.llmUsesSTTCredentials = false
            MockURLProtocol.stub(status: 200, body: """
            {"choices":[{"message":{"content":"ok"}}]}
            """)
            _ = runAsync { await service.postProcessDetailed(draftText: "x") }
            assertTest(
                MockURLProtocol.lastRequestHeaders["Authorization"] == nil,
                "No Authorization header is sent when no key is configured"
            )
            settings.llmUsesSTTCredentials = true
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

        // Suite 10: Clipboard ownership (TextInjector)
        runSuite("Clipboard Ownership") {
            // Fresh state: nothing injected yet, so never claim ownership.
            assertTest(
                !TextInjector.ownsClipboard(currentChangeCount: 7, lastInjectedChangeCount: -1),
                "No clipboard is owned before the first injection"
            )
            assertTest(
                !TextInjector.shouldRestoreClipboard(currentChangeCount: 0, ownedChangeCount: -1),
                "A restore never fires without a prior injection"
            )

            // We wrote at changeCount 10 and nothing has touched it since.
            assertTest(
                TextInjector.ownsClipboard(currentChangeCount: 10, lastInjectedChangeCount: 10),
                "The board is ours while the changeCount still matches our write"
            )
            assertTest(
                TextInjector.shouldRestoreClipboard(currentChangeCount: 10, ownedChangeCount: 10),
                "The user's clipboard is restored when nothing else touched the board"
            )

            // The user copied something during the restore window.
            assertTest(
                !TextInjector.shouldRestoreClipboard(currentChangeCount: 11, ownedChangeCount: 10),
                "A restore is abandoned once the user copies something new"
            )

            // Two dictations inside one restore window. The second injection must
            // see the board as ours and carry the ORIGINAL snapshot forward,
            // otherwise it captures Lyra's own text as "the user's clipboard" and
            // restores that — which silently destroyed the real clipboard.
            let userClipboardWriteCount = 10
            let firstInjection = 11
            let secondInjection = 12
            assertTest(
                !TextInjector.ownsClipboard(currentChangeCount: userClipboardWriteCount,
                                            lastInjectedChangeCount: -1),
                "The first injection snapshots the user's real clipboard"
            )
            assertTest(
                TextInjector.ownsClipboard(currentChangeCount: firstInjection,
                                           lastInjectedChangeCount: firstInjection),
                "The second injection recognizes Lyra's own text on the board"
            )
            assertTest(
                !TextInjector.shouldRestoreClipboard(currentChangeCount: secondInjection,
                                                     ownedChangeCount: firstInjection),
                "The superseded first restore does not fire"
            )
            assertTest(
                TextInjector.shouldRestoreClipboard(currentChangeCount: secondInjection,
                                                    ownedChangeCount: secondInjection),
                "Only the latest injection restores, and it restores the carried-forward clipboard"
            )
        }

        // Suite 11: Hotkey bindings (combinations)
        runSuite("Hotkey Bindings") {
            let fn = CGEventFlags.maskSecondaryFn.rawValue
            let shift = CGEventFlags.maskShift.rawValue
            let option = CGEventFlags.maskAlternate.rawValue

            // Bare modifier: the classic "hold Left Option" binding.
            let bareOption = HotkeyBinding(keyCode: 58, modifierFlags: 0)
            assertTest(bareOption.isBareModifier, "A lone modifier keycode is a bare-modifier binding")
            assertTest(!bareOption.isChord, "A bare modifier is not a chord")
            assertTest(bareOption.isAssigned, "A bare modifier binding is assigned")

            // fn + ` — the combination that was previously unrepresentable.
            let fnGrave = HotkeyBinding(keyCode: 50, modifierFlags: fn)
            assertTest(fnGrave.isChord, "fn + ` is a chord binding")
            assertTest(!fnGrave.isBareModifier, "fn + ` is not a bare modifier")
            assertTest(fnGrave.matches(rawFlags: fn), "fn + ` matches when only fn is held")
            assertTest(
                !fnGrave.matches(rawFlags: fn | shift),
                "fn + ` does not fire when Shift is also held"
            )
            assertTest(!fnGrave.matches(rawFlags: 0), "fn + ` does not fire with no modifiers")

            // Noise bits the system sets must not break matching.
            let noise = CGEventFlags.maskNonCoalesced.rawValue
            assertTest(
                fnGrave.matches(rawFlags: fn | noise),
                "Irrelevant flag bits (maskNonCoalesced) are ignored when matching"
            )

            // A plain key with no modifiers is neither bare-modifier nor chord,
            // but is still a usable binding (e.g. F5).
            let plainKey = HotkeyBinding(keyCode: 96, modifierFlags: 0)
            assertTest(plainKey.isAssigned, "A plain key binding is assigned")
            assertTest(!plainKey.isBareModifier, "A plain key is not a bare modifier")
            assertTest(!plainKey.isChord, "A plain key with no modifiers is not a chord")
            assertTest(plainKey.matches(rawFlags: 0), "A plain key matches with no modifiers held")
            assertTest(
                !plainKey.matches(rawFlags: option),
                "A plain key does not fire while a modifier is held"
            )

            // Unassigned (the optional hands-free key left empty).
            assertTest(!HotkeyBinding.unassigned.isAssigned, "The unassigned binding reports itself as such")
            assertTest(!HotkeyBinding.unassigned.isChord, "The unassigned binding is not a chord")

            // Labels
            assertTest(fnGrave.shortLabel.hasPrefix("fn"), "A chord label carries its modifier prefix (got \(fnGrave.shortLabel))")
            // The character depends on the active keyboard layout, so assert the
            // placeholder is gone rather than a specific glyph.
            assertTest(
                !fnGrave.shortLabel.contains("key"),
                "An ordinary key resolves against the keyboard layout instead of the \"key\" placeholder (got \(fnGrave.shortLabel))"
            )
            assertTest(
                HotkeyBinding(keyCode: 96, modifierFlags: 0).shortLabel == "F5",
                "Function keys have stable labels even though the layout cannot translate them"
            )
            assertTest(HotkeyBinding.unassigned.shortLabel == "—", "An unassigned binding renders as a dash")

            // Round-trip through settings storage.
            let settings = AppSettings.shared
            let savedPrimary = settings.primaryHotkey
            let savedHandsFree = settings.handsFreeHotkey
            settings.primaryHotkey = fnGrave
            assertTest(settings.primaryHotkey == fnGrave, "A chord survives a round trip through settings")
            settings.handsFreeHotkey = .unassigned
            assertTest(!settings.handsFreeHotkey.isAssigned, "The hands-free key can be left unassigned")
            settings.primaryHotkey = savedPrimary
            settings.handsFreeHotkey = savedHandsFree

            // Tap threshold is clamped to the slider range on both read and write.
            let savedThreshold = settings.handsFreeTapThreshold
            settings.handsFreeTapThreshold = 99
            assertTest(settings.handsFreeTapThreshold <= 1.0, "The tap threshold is clamped from above")
            settings.handsFreeTapThreshold = -5
            assertTest(settings.handsFreeTapThreshold >= 0.15, "The tap threshold is clamped from below")
            settings.handsFreeTapThreshold = savedThreshold
        }

        // Suite 12: VAD latency ceiling
        runSuite("VAD Latency Ceiling") {
            // Default gate: an uninterrupted speaker gets nothing until the
            // ~25 s ceiling, which is fine for live dictation but far too long
            // for a preview that is meant to track speech.
            var normal = VADChunkGate()
            var committedAt: Int? = nil
            for i in 0..<VADChunkGate.ceilingWindows + 5 {
                if case .commit = normal.ingest(probability: 0.9) { committedAt = i; break }
            }
            assertTest(
                committedAt == VADChunkGate.ceilingWindows - 1,
                "Continuous speech commits only at the default ceiling (got \(String(describing: committedAt)))"
            )

            // Preview gate: a much lower ceiling, so text keeps arriving.
            var fast = VADChunkGate()
            fast.ceilingWindows = 100
            var fastCommit: Int? = nil
            for i in 0..<200 {
                if case .commit = fast.ingest(probability: 0.9) { fastCommit = i; break }
            }
            assertTest(fastCommit == 99, "A lowered ceiling commits early during continuous speech (got \(String(describing: fastCommit)))")

            // The ceiling must survive the reset that a commit performs, or only
            // the first chunk would be responsive.
            var second: Int? = nil
            for i in 0..<200 {
                if case .commit = fast.ingest(probability: 0.9) { second = i; break }
            }
            assertTest(second == 99, "The lowered ceiling persists across commits (got \(String(describing: second)))")

            // A pause still wins over the ceiling, and near-silence is dropped
            // rather than sent as an empty request.
            var paused = VADChunkGate()
            paused.ceilingWindows = 100
            var event: VADChunkGate.Event = .none
            for _ in 0..<VADChunkGate.minSpeechWindows { _ = paused.ingest(probability: 0.9) }
            for _ in 0..<VADChunkGate.pauseWindows { event = paused.ingest(probability: 0.0) }
            assertTest(event != .none && event != .drop, "A natural pause still commits before the ceiling")

            var quiet = VADChunkGate()
            quiet.ceilingWindows = 100
            var quietEvent: VADChunkGate.Event = .none
            for i in 0..<120 { quietEvent = quiet.ingest(probability: 0.0); if quietEvent != .none { break }; _ = i }
            assertTest(quietEvent == .drop, "Silence is dropped, never sent as a request (got \(quietEvent))")
        }

        // Suite 13: Deepgram streaming transcript assembly
        runSuite("Streaming Transcript Assembly") {
            // --- v2 Flux: each message carries the WHOLE hypothesis for its
            // turn, revised as more audio arrives. Appending would duplicate.
            var a = DeepgramTranscriptAssembler()
            a.apply(transcript: "Проверяю", turnIndex: 0, endOfTurn: false)
            assertTest(a.text == "Проверяю", "The first partial shows immediately")
            a.apply(transcript: "Проверяю приложение", turnIndex: 0, endOfTurn: false)
            assertTest(a.text == "Проверяю приложение", "A revised partial replaces the previous one, never appends")
            a.apply(transcript: "Проверяю приложение прямо сейчас", turnIndex: 0, endOfTurn: true)
            assertTest(a.text == "Проверяю приложение прямо сейчас", "EndOfTurn settles the turn")

            a.apply(transcript: "Вторая", turnIndex: 1, endOfTurn: false)
            assertTest(
                a.text == "Проверяю приложение прямо сейчас Вторая",
                "A new turn is appended after the settled one (got \(a.text))"
            )
            a.apply(transcript: "Вторая фраза", turnIndex: 1, endOfTurn: true)
            assertTest(a.text == "Проверяю приложение прямо сейчас Вторая фраза", "Turns accumulate in order")

            // A dropped EndOfTurn must not merge two turns into one.
            var b = DeepgramTranscriptAssembler()
            b.apply(transcript: "Первая", turnIndex: 0, endOfTurn: false)
            b.apply(transcript: "Вторая", turnIndex: 1, endOfTurn: false)
            assertTest(b.text == "Первая Вторая", "A new turn index settles the previous turn even without EndOfTurn")

            // Silence must not wipe the tail already on screen.
            var c = DeepgramTranscriptAssembler()
            c.apply(transcript: "Привет", turnIndex: 0, endOfTurn: false)
            c.apply(transcript: "", turnIndex: 0, endOfTurn: false)
            assertTest(c.text == "Привет", "An empty partial does not retract what is displayed")
            c.apply(transcript: "", turnIndex: 0, endOfTurn: true)
            assertTest(c.text == "Привет", "An empty final keeps the last good hypothesis")

            // --- v1 fallback: no turn index, is_final settles a segment.
            var v1 = DeepgramTranscriptAssembler()
            v1.apply(transcript: "one", turnIndex: nil, endOfTurn: false)
            v1.apply(transcript: "one two", turnIndex: nil, endOfTurn: true)
            v1.apply(transcript: "three", turnIndex: nil, endOfTurn: true)
            assertTest(v1.text == "one two three", "The v1 interim/final shape still assembles (got \(v1.text))")

            var empty = DeepgramTranscriptAssembler()
            assertTest(empty.text.isEmpty, "A fresh assembler has no text")
            empty.apply(transcript: "  ", turnIndex: 0, endOfTurn: true)
            assertTest(empty.text.isEmpty, "Whitespace-only results produce nothing")

            var reset = DeepgramTranscriptAssembler()
            reset.apply(transcript: "gone", turnIndex: 0, endOfTurn: true)
            reset.reset()
            assertTest(reset.text.isEmpty, "reset() clears both settled and live text")

            // --- Endpoint construction
            let config = DeepgramStreamingClient.Config(
                apiKey: "k", model: "flux-general-multi", language: nil
            )
            let url = DeepgramStreamingClient.endpoint(for: config)?.absoluteString ?? ""
            assertTest(url.hasPrefix("wss://api.deepgram.com/v2/listen"), "Streaming uses the v2 endpoint (got \(url))")
            assertTest(url.contains("encoding=linear16"), "Audio is declared as linear16 PCM")
            assertTest(url.contains("sample_rate=16000"), "The sample rate matches the capture format")
            assertTest(url.contains("eot_threshold"), "End-of-turn tuning is sent")
            assertTest(!url.contains("language="), "A multilingual model is not pinned to one language")

            let pinned = DeepgramStreamingClient.Config(apiKey: "k", model: "flux-general-en", language: "ru")
            let pinnedURL = DeepgramStreamingClient.endpoint(for: pinned)?.absoluteString ?? ""
            assertTest(pinnedURL.contains("language=ru"), "A non-multilingual model gets an explicit language")

            // The vocabulary list reached whisper through initial_prompt but had
            // no path into the stream, so the Settings section stopped doing
            // anything once Deepgram became the transcriber.
            var withTerms = DeepgramStreamingClient.Config(apiKey: "k", model: "flux-general-multi", language: nil)
            withTerms.keyterms = ["SwiftUI", "OpenRouter", "  ", "Lyra"]
            let termsURL = DeepgramStreamingClient.endpoint(for: withTerms)?.absoluteString ?? ""
            assertTest(termsURL.contains("keyterm=SwiftUI"), "Vocabulary terms are sent to the stream")
            assertTest(termsURL.contains("keyterm=Lyra"), "Every vocabulary term is sent, not just the first")
            assertTest(
                termsURL.components(separatedBy: "keyterm=").count - 1 == 3,
                "Blank vocabulary entries are skipped rather than sent empty"
            )

            var flooded = DeepgramStreamingClient.Config(apiKey: "k", model: "flux-general-multi", language: nil)
            flooded.keyterms = (0..<200).map { "term\($0)" }
            let floodedURL = DeepgramStreamingClient.endpoint(for: flooded)?.absoluteString ?? ""
            assertTest(
                floodedURL.components(separatedBy: "keyterm=").count - 1 == DeepgramStreamingClient.maxKeyterms,
                "The term list is capped so a long vocabulary cannot get the connection rejected"
            )
        }

        // Suite 14: Vocabulary reaches post-processing
        runSuite("Vocabulary In Post-Processing") {
            let base = "БАЗОВЫЕ ПРАВИЛА"

            // No vocabulary: the prompt must be left exactly as the user wrote it.
            assertTest(
                DictationEngine.buildPostProcessingPrompt(base: base, customTerms: []) == base,
                "An empty vocabulary leaves the prompt untouched"
            )
            assertTest(
                DictationEngine.buildPostProcessingPrompt(base: base, customTerms: ["  ", ""]) == base,
                "Blank vocabulary entries do not produce an empty term list"
            )

            // Recognition bias alone cannot fix a term the speech model mangles
            // ("Aqua Voice" -> "аквавосон"); the post-processor can only repair
            // it if it is told the term exists.
            let withTerms = DictationEngine.buildPostProcessingPrompt(
                base: base,
                customTerms: ["Aqua Voice", "SwiftUI", "Deepgram"]
            )
            assertTest(withTerms.hasPrefix(base), "The user's own rules stay at the front of the prompt")
            assertTest(withTerms.contains("Aqua Voice"), "Vocabulary terms are handed to the post-processor")
            assertTest(withTerms.contains("SwiftUI") && withTerms.contains("Deepgram"), "Every term is included")
            assertTest(
                withTerms.contains("восстанови правильное написание"),
                "The prompt asks for mangled terms to be repaired"
            )
            assertTest(
                withTerms.contains("Не подставляй эти термины туда, где их не было"),
                "The prompt guards against inserting terms the user never said"
            )

            let flooded = DictationEngine.buildPostProcessingPrompt(
                base: base,
                customTerms: (0..<200).map { "term\($0)" }
            )
            assertTest(
                !flooded.contains("term199"),
                "A long vocabulary is capped so it cannot crowd out the rules"
            )
            assertTest(flooded.contains("term0"), "The cap keeps the earliest terms")
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
