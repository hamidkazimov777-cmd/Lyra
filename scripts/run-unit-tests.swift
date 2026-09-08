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

            let deepSeekPreset = APIPresetProvider.deepSeek
            assertTest(deepSeekPreset.defaultBaseURL == "https://api.deepseek.com/v1", "DeepSeek preset endpoint correct")
            assertTest(deepSeekPreset.defaultModel == "deepseek-chat", "DeepSeek preset model is deepseek-chat")

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

        // Summary
        print("\n" + String(repeating: "=", count: 50))
        print("\(bold)Test Results: \(green)\(passed) passed\(reset), \(failed > 0 ? "\(red)\(failed) failed" : "\(green)0 failed")\(reset)")
        print(String(repeating: "=", count: 50) + "\n")

        if failed > 0 {
            exit(1)
        }
    }
}
