import Foundation
import Combine
import Cocoa

enum DictationState: String {
    case idle
    case recording
    case processing
    case typing
}

final class DictationEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var lastTranscription: String = ""
    @Published private(set) var liveTranscription: String = ""
    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var modelLoadError: String?

    /// Last transcription/recording failure surfaced to the user (inference failure,
    /// audio input configuration change). Cleared when a new recording starts and on
    /// the next successful dictation.
    @Published private(set) var transcriptionError: String?

    /// True while the user is holding the hotkey in legacy mode.
    @Published private(set) var isHoldingForToggle: Bool = false

    /// True when hands-free recording is currently running.
    @Published private(set) var isHandsFreeActive: Bool = false

    /// True when recording with highlighted text selected in active application (Smart Edit mode).
    @Published private(set) var isSmartEditActive: Bool = false

    let coordinator = TranscriptionCoordinator.shared

    var isFallbackActive: Bool {
        coordinator.isFallbackActive
    }

    var isReadyToRecord: Bool {
        AppSettings.shared.transcriptionProviderType == .api || isModelLoaded
    }

    private var whisperBridge: WhisperBridge?
    private let audioCapture = AudioCapture()
    private let textInjector = TextInjector()
    private let soundFeedback = SoundFeedback()
    private var hotkeyMonitor: HotkeyMonitor?
    private var capturedSelectedText: String?

    private let minRecordingDuration: TimeInterval = 0.3
    private var recordingStartTime: Date?
    private var lastHotkeyToggleTimestamp: TimeInterval = 0
    private var hotkeyDownTimestamp: TimeInterval = 0
    private var isRecordingStartedByHotkey: Bool = false
    private var inFlightCancelFlag: CancellationFlag?

    private var accessibilityPoller: Timer?

    init(audioLevelAnalyzer: AudioLevelAnalyzer? = nil) {
        let axTrusted = PermissionManager.shared.requestAccessibility()
        fputs("[DictationEngine] Init. Accessibility: \(axTrusted)\n", stderr)
        audioCapture.audioLevelAnalyzer = audioLevelAnalyzer
        audioCapture.onConfigurationChange = { [weak self] in
            self?.handleInputConfigurationChange()
        }
        audioCapture.onMaxDurationReached = { [weak self] in
            self?.handleMaxRecordingDurationReached()
        }
        setupHotkeyMonitor()
        hotkeyMonitor?.start()
        loadModelAsync()
        LaunchAtLoginHelper.reconcile()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.prepareForTermination()
        }

        if !axTrusted {
            startAccessibilityPoller()
        }
    }

    private func startAccessibilityPoller() {
        accessibilityPoller?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                fputs("[DictationEngine] Accessibility granted! Restarting hotkey monitor.\n", stderr)
                timer.invalidate()
                self?.accessibilityPoller = nil
                PermissionManager.shared.accessibilityGranted = true
                self?.transcriptionError = nil
                self?.restartHotkeyMonitor()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessibilityPoller = timer
    }

    func restartHotkeyMonitor() {
        cancelPendingToggle()
        hotkeyMonitor?.stop()
        setupHotkeyMonitor()
        hotkeyMonitor?.start()
    }

    // MARK: - Model Loading

    private func loadModelAsync() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let modelPath = ModelManager.shared.activeModelPath()
                guard let modelPath else {
                    await MainActor.run {
                        self.modelLoadError = "No model found. Open Settings to download a model."
                    }
                    return
                }
                let bridge = try WhisperBridge(modelPath: modelPath)

                // Pre-warm GPU: JIT-compile Metal shaders with a tiny dummy inference.
                // Async so this cooperative-pool task isn't blocked during warmup.
                await bridge.warmup()

                await MainActor.run {
                    self.whisperBridge = bridge
                    self.isModelLoaded = true
                    self.modelLoadError = nil
                }
            } catch {
                await MainActor.run {
                    self.modelLoadError = "Failed to load model: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Set when `reloadModel()` is requested while a transcription is in flight.
    /// Consumed on the return to idle. Main-actor only.
    private var pendingModelReload = false

    /// Swap the active model. If a transcription is mid-flight (`.recording` captured
    /// no bridge yet, but `.processing`/`.typing` hold the current bridge locally and
    /// must finish on it), nulling `whisperBridge` here would strand that task or drop
    /// the utterance. So only reload immediately when idle; otherwise defer until the
    /// engine returns to idle (the new selection is already persisted in AppSettings,
    /// so the deferred reload picks it up). Called on the main actor.
    func reloadModel() {
        guard state == .idle else {
            pendingModelReload = true
            return
        }
        performModelReload()
    }

    private func performModelReload() {
        pendingModelReload = false
        isModelLoaded = false
        modelLoadError = nil
        whisperBridge = nil
        loadModelAsync()
    }

    /// Transition to idle and, if a model reload was deferred while the engine was
    /// busy, perform it now. Main-actor only.
    private func returnToIdle() {
        state = .idle
        isHandsFreeActive = false
        isSmartEditActive = false
        capturedSelectedText = nil
        liveTranscription = ""
        drainCancelFlag = nil
        inFlightCancelFlag = nil
        audioCapture.audioLevelAnalyzer?.reset()
        if pendingModelReload { performModelReload() }
    }

    // MARK: - Hotkey

    private func setupHotkeyMonitor() {
        hotkeyMonitor = HotkeyMonitor(
            onKeyDown: { [weak self] in self?.handleKeyDown() },
            onKeyUp: { [weak self] in self?.handleKeyUp() }
        )
    }

    func startMonitoring() {
        hotkeyMonitor?.start()
    }

    func stopMonitoring() {
        cancelPendingToggle()
        hotkeyMonitor?.stop()
    }

    private func cancelPendingToggle() {
        if isHoldingForToggle { isHoldingForToggle = false }
    }

    // MARK: - Hotkey Mode Dispatch

    enum KeyDownAction: Equatable { case startRecording, stopRecording, cancelTranscription }

    static func keyDownAction(mode: AppSettings.HotkeyMode, state: DictationState) -> KeyDownAction {
        switch mode {
        case .pushToTalk:
            return (state == .processing || state == .typing) ? .cancelTranscription : .startRecording
        case .toggle:
            switch state {
            case .idle:
                return .startRecording
            case .recording:
                return .stopRecording
            case .processing, .typing:
                return .cancelTranscription
            }
        }
    }

    private func handleKeyDown() {
        let now = Date().timeIntervalSince1970
        hotkeyDownTimestamp = now

        if state == .processing || state == .typing {
            cancelTranscription()
            return
        }

        if state == .recording {
            // Hotkey pressed while already recording: stop recording and transcribe!
            guard now - lastHotkeyToggleTimestamp > 0.25 else { return }
            lastHotkeyToggleTimestamp = now
            isHandsFreeActive = false
            stopRecordingAndTranscribe()
            return
        }

        // Idle state: start recording
        guard now - lastHotkeyToggleTimestamp > 0.25 else { return }
        lastHotkeyToggleTimestamp = now

        isRecordingStartedByHotkey = true
        isHandsFreeActive = (AppSettings.shared.hotkeyMode == .toggle)
        startRecording()
    }

    /// Ask active transcription to abort immediately.
    private func cancelTranscription() {
        fputs("[DictationEngine] Cancel requested during \(state.rawValue).\n", stderr)
        isSmartEditActive = false
        capturedSelectedText = nil
        inFlightCancelFlag?.cancel()
        if let liveFlagForDrain = drainCancelFlag {
            liveFlagForDrain.cancel()
        } else {
            whisperBridge?.cancelTranscription()
        }
    }

    private func handleKeyUp() {
        guard isRecordingStartedByHotkey else { return }
        let duration = Date().timeIntervalSince1970 - hotkeyDownTimestamp

        if AppSettings.shared.hotkeyMode == .toggle {
            // Pure toggle mode: releasing does nothing
            return
        }

        // Push-to-Talk mode:
        // Smart key handling:
        // If key was held for >= 0.35s: standard Push-to-Talk (release stops and transcribes)
        // If key was quickly tapped (< 0.35s): don't discard! Keep recording hands-free.
        if duration >= 0.35 {
            fputs("[DictationEngine] Key held for \(String(format: "%.2f", duration))s - push-to-talk stop.\n", stderr)
            isRecordingStartedByHotkey = false
            isHandsFreeActive = false
            stopRecordingAndTranscribe()
        } else {
            fputs("[DictationEngine] Key tapped for \(String(format: "%.2f", duration))s - keeping hands-free recording.\n", stderr)
            isHandsFreeActive = true
        }
    }

    /// Toggles dictation mode (start if idle, stop and transcribe if recording).
    /// Safe to call from UI buttons, menus, and floating widgets.
    func toggleRecording() {
        switch state {
        case .idle:
            if !AXIsProcessTrusted() {
                PermissionManager.shared.requestAccessibility()
                PermissionManager.shared.openAccessibilitySettings()
            }
            isHandsFreeActive = true
            startRecording()
        case .recording:
            isHandsFreeActive = false
            stopRecordingAndTranscribe()
        case .processing, .typing:
            cancelTranscription()
        }
    }

    // MARK: - Prompt Assembly

    /// Whisper's initial_prompt is capped at ~1024 tokens (~750 words). Exceeding it
    /// triggers `whisper_tokenize: too many resulting tokens` and degrades accuracy
    /// (see CLAUDE.md). We budget 700 words as a safe margin.
    static let promptWordBudget = 700

    /// Builds the whisper initial_prompt from the base vocabulary prompt plus the
    /// user's custom terms, staying within `promptWordBudget` words. The base prompt
    /// is truncated first if it alone exceeds the budget; custom terms then fill any
    /// remaining word budget. Pure/static so it is unit-testable without the engine.
    ///
    /// - Parameter transcriptTail: text already committed in this dictation, used by
    ///   live mode so each chunk decodes with the preceding words as context. Empty
    ///   (the default) leaves the prompt byte-identical to the non-live build.
    static func buildPrompt(base: String, customTerms: [String], transcriptTail: String = "") -> String {
        let baseWords = base.split(separator: " ")
        let cappedBase = baseWords.count > promptWordBudget
            ? baseWords.prefix(promptWordBudget).joined(separator: " ")
            : base

        let termBudget = max(0, promptWordBudget - baseWords.count)
        let termsToAdd = Array(customTerms.prefix(termBudget))
        let withTerms = termsToAdd.isEmpty
            ? cappedBase
            : cappedBase + ", " + termsToAdd.joined(separator: ", ")

        // Committed-transcript tail: budgeted by ACTUAL word count (terms above
        // deliberately keep their historical one-unit-each accounting), capped
        // at 50 words, appended last — closest to the decode.
        let tailWords = transcriptTail.split(separator: " ")
        let usedWords = min(baseWords.count, promptWordBudget) + termsToAdd.count
        let tailBudget = min(50, max(0, promptWordBudget - usedWords))
        guard tailBudget > 0, !tailWords.isEmpty else { return withTerms }
        return withTerms + " " + tailWords.suffix(tailBudget).joined(separator: " ")
    }

    // MARK: - Recording Flow

    private func startRecording() {
        guard state == .idle else { return }

        guard AXIsProcessTrusted() else {
            PermissionManager.shared.requestAccessibility()
            PermissionManager.shared.openAccessibilitySettings()
            transcriptionError = "Accessibility access required to insert text. Enable Lyra in System Settings → Privacy & Security → Accessibility."
            fputs("[DictationEngine] Accessibility not granted. Prompting user.\n", stderr)
            return
        }

        guard isReadyToRecord else {
            transcriptionError = "Model is still loading. Please wait a moment..."
            fputs("[DictationEngine] Engine not ready to record yet.\n", stderr)
            return
        }

        transcriptionError = nil
        liveTranscription = ""
        state = .recording
        recordingStartTime = Date()
        soundFeedback.playStartSound()

        // Inspect highlighted selection in frontmost application for Smart Edit mode
        if AppSettings.shared.smartVoiceEditingEnabled {
            capturedSelectedText = SelectedTextReader.getSelectedText()
            isSmartEditActive = (capturedSelectedText != nil)
        } else {
            capturedSelectedText = nil
            isSmartEditActive = false
        }

        let live = startLiveSessionIfEnabled()
        fputs("[DictationEngine] Recording (live: \(live), smartEdit: \(isSmartEditActive))\n", stderr)

        do {
            try audioCapture.startRecording()
        } catch {
            fputs("[DictationEngine] Failed to start recording: \(error)\n", stderr)
            isSmartEditActive = false
            capturedSelectedText = nil
            teardownLiveSession()
            state = .idle
            isHandsFreeActive = false
        }
    }

    /// - Parameter trimTrailingSeconds: number of seconds to trim from the end of the audio
    ///   buffer before transcription. Used by toggle mode to discard the silent hold-to-stop
    ///   interval (otherwise Whisper hallucinates trailing punctuation/filler from the silence).
    ///   Push-to-talk passes 0.
    private func stopRecordingAndTranscribe(trimTrailingSeconds: TimeInterval = 0) {
        guard state == .recording else { return }
        if isLiveSession {
            isSmartEditActive = false
            capturedSelectedText = nil
            stopLiveSession(trimTrailingSeconds: trimTrailingSeconds)
            return
        }

        let selectedTextToTransform = self.capturedSelectedText
        self.capturedSelectedText = nil

        let audioBuffer = audioCapture.stopRecording(trimTrailingSeconds: trimTrailingSeconds)
        soundFeedback.playStopSound()

        // Check minimum duration
        if let start = recordingStartTime,
           Date().timeIntervalSince(start) < minRecordingDuration {
            if !isHandsFreeActive {
                returnToIdle()
                return
            }
        }

        guard !audioBuffer.isEmpty else {
            returnToIdle()
            return
        }

        state = .processing
        isHandsFreeActive = false

        let bridge = self.whisperBridge
        let prompt = Self.buildPrompt(
            base: AppSettings.shared.vocabularyPrompt,
            customTerms: AppSettings.shared.customTerms
        )
        let injector = self.textInjector
        let feedback = self.soundFeedback
        let coordinator = self.coordinator
        let cancelFlag = CancellationFlag()
        self.inFlightCancelFlag = cancelFlag

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Wait for all enqueued typing to drain, then surface the result and go idle.
            func finish(transcript: String?, error: String?) async {
                injector.flush()
                await MainActor.run {
                    self.inFlightCancelFlag = nil
                    self.liveTranscription = ""
                    if let error { self.transcriptionError = error }
                    if let transcript, !transcript.isEmpty {
                        self.lastTranscription = transcript
                        self.transcriptionError = nil
                    }
                    feedback.playDoneSound()
                    self.returnToIdle()
                }
            }

            await MainActor.run {
                self.state = .typing
            }

            let collected = TranscriptCollector()
            let aiPostProcess = AppSettings.shared.aiPostProcessingEnabled
            let rawTranscript: String
            do {
                rawTranscript = try await coordinator.transcribe(
                    samples: audioBuffer,
                    language: AppSettings.shared.selectedLanguage,
                    prompt: prompt,
                    cancelFlag: cancelFlag,
                    localBridge: bridge
                ) { segment in
                    if aiPostProcess {
                        _ = collected.joinAndAppend(segment)
                        Task { @MainActor in
                            self.liveTranscription = segment
                        }
                    } else {
                        let corrected = TextCorrector.shared.correct(segment, language: AppSettings.shared.selectedLanguage)
                        Task { @MainActor in
                            self.liveTranscription = corrected
                        }
                        injector.type(text: collected.joinAndAppend(corrected))
                    }
                }
            } catch let error as WhisperError where error.isCancellation {
                fputs("[DictationEngine] Transcription cancelled by user.\n", stderr)
                await finish(transcript: nil, error: nil)
                return
            } catch let error as TranscriptionServiceError where error.isCancellation {
                fputs("[DictationEngine] Transcription cancelled by user.\n", stderr)
                await finish(transcript: nil, error: nil)
                return
            } catch {
                fputs("[DictationEngine] Transcription failed: \(error)\n", stderr)
                await finish(transcript: nil, error: error.localizedDescription)
                return
            }

            if cancelFlag.isCancelled {
                await finish(transcript: nil, error: nil)
                return
            }

            var finalText = collected.text.isEmpty ? rawTranscript : collected.text
            finalText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)

            var postProcessingError: String? = nil

            // 1. Smart Edit / Voice Transform Mode (if user had selected text)
            if let originalSelected = selectedTextToTransform, !originalSelected.isEmpty {
                let postModelName = AppSettings.shared.aiPostProcessingModelDisplayName
                await MainActor.run {
                    self.liveTranscription = "✨ Smart Edit: \(postModelName)..."
                }

                let result = await coordinator.apiService.transformSelectedText(
                    originalText: originalSelected,
                    instruction: finalText,
                    model: AppSettings.shared.aiPostProcessingModel,
                    timeoutSeconds: AppSettings.shared.aiPostProcessingTimeoutSeconds + 4.0
                )

                if cancelFlag.isCancelled {
                    await finish(transcript: nil, error: nil)
                    return
                }

                finalText = result.text
                injector.type(text: finalText)

                if result.success {
                    await MainActor.run {
                        self.liveTranscription = "✓ Smart Edit (\(String(format: "%.1f", result.elapsedSeconds))s)"
                    }
                    try? await Task.sleep(nanoseconds: 350_000_000)
                } else {
                    let errSnippet = result.errorMessage?.prefix(35) ?? "Failed"
                    await MainActor.run {
                        self.liveTranscription = "⚠️ \(errSnippet)"
                    }
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }

                await finish(transcript: finalText, error: nil)

                let modelTag = "\(coordinator.lastUsedProvider) + Smart Edit (\(postModelName))"
                HistoryStore.shared.add(
                    text: "✨ [Edit: \(rawTranscript.prefix(35))] \(finalText)",
                    language: AppSettings.shared.selectedLanguage,
                    modelName: modelTag
                )
                return
            }

            // 2. Regular Dictation AI Post-Processing
            if aiPostProcess && !finalText.isEmpty {
                let postModelName = AppSettings.shared.aiPostProcessingModelDisplayName
                await MainActor.run {
                    self.liveTranscription = "✨ \(postModelName)..."
                }

                let result = await coordinator.apiService.postProcessDetailed(
                    draftText: finalText,
                    model: AppSettings.shared.aiPostProcessingModel,
                    systemPrompt: AppSettings.shared.aiPostProcessingPrompt,
                    timeoutSeconds: AppSettings.shared.aiPostProcessingTimeoutSeconds
                )

                if cancelFlag.isCancelled {
                    await finish(transcript: nil, error: nil)
                    return
                }

                finalText = result.text
                injector.type(text: finalText)

                if result.success {
                    await MainActor.run {
                        self.liveTranscription = "✓ \(postModelName) (\(String(format: "%.1f", result.elapsedSeconds))s)"
                    }
                    try? await Task.sleep(nanoseconds: 350_000_000)
                } else {
                    postProcessingError = result.errorMessage
                    let errSnippet = result.errorMessage?.prefix(35) ?? "Failed"
                    await MainActor.run {
                        self.liveTranscription = "⚠️ \(errSnippet)"
                    }
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
            }

            await finish(transcript: finalText, error: nil)

            let modelTag: String
            if aiPostProcess {
                let name = AppSettings.shared.aiPostProcessingModelDisplayName
                if let err = postProcessingError {
                    modelTag = "\(coordinator.lastUsedProvider) + \(name) (⚠️ \(err.prefix(25)))"
                } else {
                    modelTag = "\(coordinator.lastUsedProvider) + \(name)"
                }
            } else {
                modelTag = coordinator.lastUsedProvider
            }

            HistoryStore.shared.add(
                text: finalText,
                language: AppSettings.shared.selectedLanguage,
                modelName: modelTag
            )
        }
    }

    // MARK: - Live Dictation Session

    private enum LiveWorkItem {
        case chunk([Float])
        case residual([Float])
    }

    /// Residual minimum is SAMPLE COUNT (≈0.3 s @16 kHz) — the wall-clock
    /// minRecordingDuration check measures the whole session and would always
    /// pass after a live session. Distinct from VADChunkGate.minSpeechWindows,
    /// which gates chunks by accumulated speech, not raw length.
    static let residualMinSeconds = 0.3
    static func residualMeetsMinimum(sampleCount: Int) -> Bool {
        Double(sampleCount) >= 16000 * residualMinSeconds
    }

    /// Stop-time termination (append-only): a session whose committed text
    /// never ended a sentence gets exactly one period at stop. Chunks are
    /// never auto-terminated (a "final chunk" is unknowable at commit time —
    /// toggle mode's hold-to-stop guarantees the last utterance commits as an
    /// intermediate chunk).
    static func needsTerminalPeriod(committed: String) -> Bool {
        guard let last = committed.last else { return false }
        return !".!?".contains(last)
    }

    private var liveSegmenter: VADSegmenter?
    private var liveContinuation: AsyncStream<LiveWorkItem>.Continuation?
    private var liveSessionFlag: CancellationFlag?

    /// The session flag kept alive for the drain phase (stop → consumer finish),
    /// after the main-actor session references are cleared. This is what a cancel
    /// during .processing/.typing flips. Cleared in `returnToIdle()`.
    private var drainCancelFlag: CancellationFlag?

    private var isLiveSession: Bool { liveSegmenter != nil }

    /// Engine-side guard (evaluated per session): the setting stores intent;
    /// live runs only when the VAD model is actually on disk, resolved fresh
    /// (WhisperBridge's cached copy from its own init must not be reused).
    private func startLiveSessionIfEnabled() -> Bool {
        guard AppSettings.shared.liveDictationEnabled,
              let vadPath = ModelManager.shared.vadModelPath(),
              let bridge = whisperBridge else { return false }
        do {
            let segmenter = try VADSegmenter(vadModelPath: vadPath)
            let sessionFlag = CancellationFlag()
            let (stream, continuation) = AsyncStream.makeStream(of: LiveWorkItem.self)

            liveSegmenter = segmenter
            liveContinuation = continuation
            liveSessionFlag = sessionFlag

            // Invoked synchronously on the segmenter's queue, so it must touch
            // NO main-actor state: the continuation is captured by value, never
            // read back through `self.liveContinuation`. `yield` is thread-safe
            // and non-blocking, and the stop path's `finishAndCollectResidual()`
            // barrier happens-after every commit's yield — so every committed
            // chunk is in the stream before the residual and `finish()`, and none
            // can be orphaned by the stop path clearing `liveContinuation`.
            segmenter.onChunk = { chunk in continuation.yield(.chunk(chunk)) }
            audioCapture.onSamples = { samples in segmenter.append(samples) }
            segmenter.start()
            runLiveConsumer(stream: stream, bridge: bridge, sessionFlag: sessionFlag)
            return true
        } catch {
            fputs("[DictationEngine] VAD init failed — falling back to non-live: \(error)\n", stderr)
            return false
        }
    }

    /// ONE sequential consumer: strict output order and a natural drain point
    /// fall out of the single loop (per-chunk Tasks would guarantee neither).
    /// Owns the whole post-stream finish: terminal period, flush, done sound,
    /// lastTranscription, returnToIdle — unconditionally, even when the
    /// residual was empty (the common case; the non-live empty shortcut must
    /// never be taken here or queued typing gets stranded).
    private func runLiveConsumer(
        stream: AsyncStream<LiveWorkItem>,
        bridge: WhisperBridge,
        sessionFlag: CancellationFlag
    ) {
        let injector = self.textInjector
        let feedback = self.soundFeedback
        let collected = TranscriptCollector()

        Task.detached(priority: .userInitiated) { [weak self] in
            var surfacedError: String?

            for await item in stream {
                if sessionFlag.isCancelled && surfacedError == nil {
                    continue   // user cancel during drain: skip remaining work silently
                }
                let (samples, isResidual): ([Float], Bool)
                switch item {
                case .chunk(let s): (samples, isResidual) = (s, false)
                case .residual(let s): (samples, isResidual) = (s, true)
                }
                guard surfacedError == nil else { continue }  // failure: drain and discard

                let prompt = Self.buildPrompt(
                    base: AppSettings.shared.vocabularyPrompt,
                    customTerms: AppSettings.shared.customTerms,
                    transcriptTail: collected.text
                )
                do {
                    _ = try await bridge.transcribe(
                        audioBuffer: samples,
                        language: AppSettings.shared.selectedLanguage,
                        prompt: prompt,
                        cancelFlag: sessionFlag,
                        vad: isResidual   // chunks are pre-trimmed; residual is raw
                    ) { segment in
                        let context = CorrectionContext(
                            atSentenceStart: collected.atSentenceStart,
                            appendPeriod: false   // termination is the stop-time rule
                        )
                        let corrected = TextCorrector.shared.correct(segment, context: context, language: AppSettings.shared.selectedLanguage)
                        guard !corrected.isEmpty else { return }
                        injector.type(text: collected.joinAndAppend(corrected))
                    }
                } catch let error as WhisperError where error.isCancellation {
                    continue   // silent: user cancel, or cascade after a failure
                } catch {
                    fputs("[DictationEngine] Live decode failed: \(error)\n", stderr)
                    surfacedError = error.localizedDescription
                    sessionFlag.cancel()   // abort the queue; cascade drains silently above
                }
            }

            // Stream closed: stop-time finish (unconditional drain + flush).
            if surfacedError == nil, Self.needsTerminalPeriod(committed: collected.text) {
                injector.type(text: ".")
            }
            injector.flush()

            let finalError = surfacedError
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let finalError {
                    self.transcriptionError = finalError
                } else if !collected.text.isEmpty {
                    var transcript = collected.text
                    if Self.needsTerminalPeriod(committed: transcript) { transcript += "." }
                    self.lastTranscription = transcript
                    self.transcriptionError = nil

                    HistoryStore.shared.add(
                        text: transcript,
                        language: AppSettings.shared.selectedLanguage,
                        modelName: ModelManager.shared.activeModelName()
                    )
                }
                feedback.playDoneSound()
                self.returnToIdle()
            }
        }
    }

    /// Live stop: discard the full capture buffer (its speech was already
    /// committed chunk-by-chunk), collect the segmenter's residual, and close
    /// the stream — the consumer owns everything after this point, including
    /// returnToIdle. State moves to .processing/.typing to cover the drain.
    private func stopLiveSession(trimTrailingSeconds: TimeInterval) {
        audioCapture.onSamples = nil
        _ = audioCapture.stopRecording()   // tap removed; buffer intentionally discarded
        soundFeedback.playStopSound()
        recordingStartTime = nil

        var residual = liveSegmenter?.finishAndCollectResidual() ?? []
        if trimTrailingSeconds > 0 {
            let toTrim = Int(trimTrailingSeconds * 16000)
            residual = residual.count > toTrim ? Array(residual.dropLast(toTrim)) : []
        }

        state = .processing
        if Self.residualMeetsMinimum(sampleCount: residual.count) {
            state = .typing
            liveContinuation?.yield(.residual(residual))
        }
        liveContinuation?.finish()   // consumer drains, flushes, returns to idle
        drainCancelFlag = liveSessionFlag
        clearLiveSessionReferences()
    }

    /// Drop main-actor references to the session. The consumer task holds its
    /// own copies (stream, flag, collector) and finishes independently.
    private func clearLiveSessionReferences() {
        liveSegmenter = nil
        liveContinuation = nil
        liveSessionFlag = nil
    }

    /// App is terminating (main thread; exit() follows, skipping all deinits).
    /// Stop capture, tear down any live session, and free the whisper context
    /// explicitly via `shutdownAndFree()` — ggml's at-exit Metal assert fires if
    /// it is still alive, and refcounted deinit cannot be relied on here: a
    /// live-session consumer task holds its own bridge reference and finishes
    /// on the main actor, which is blocked in this very handler. The segmenter's
    /// VAD context is CPU-only (not implicated in the Metal assert); its release
    /// through teardown stays best-effort.
    private func prepareForTermination() {
        fputs("[DictationEngine] Terminating — freeing whisper context\n", stderr)
        audioCapture.onSamples = nil
        if audioCapture.isRecording { _ = audioCapture.stopRecording() }
        // Cancel BEFORE the teardown drain so chunks committed during the drain
        // abort instead of starting fresh decodes (same rule as teardownLiveSession).
        liveSessionFlag?.cancel()
        teardownLiveSession()
        whisperBridge?.shutdownAndFree()
        whisperBridge = nil
        fputs("[DictationEngine] Whisper context freed\n", stderr)
    }

    /// Full teardown for paths where the consumer must ALSO stop (start
    /// failure, config change): close the stream so the consumer's finish
    /// block runs, then clear references.
    private func teardownLiveSession() {
        audioCapture.onSamples = nil
        _ = liveSegmenter?.finishAndCollectResidual()   // discard residual
        liveContinuation?.finish()
        // Same hand-off as stopLiveSession: a cancel arriving during this drain
        // must flip the session flag deterministically. Without it the cancel
        // falls through to the bridge's single-flight flag, which only happens
        // to work while a chunk decode is in flight. Cleared in returnToIdle().
        drainCancelFlag = liveSessionFlag
        clearLiveSessionReferences()
    }

    /// Invoked (on the audio tap thread) when a recording reaches the maximum
    /// duration cap. Route it through the normal stop-and-transcribe path on the main
    /// actor so what was captured is still transcribed, and surface a brief,
    /// non-error explanation. `stopRecordingAndTranscribe()` leaves any transcript we
    /// produce intact (it clears the status on success once text is typed).
    private func handleMaxRecordingDurationReached() {
        Task { @MainActor [weak self] in
            guard let self, self.state == .recording else { return }
            fputs("[DictationEngine] Max recording duration reached — transcribing what was captured.\n", stderr)
            self.stopRecordingAndTranscribe()
            // Set after stop so it isn't cleared by startRecording's reset; visible
            // during processing until the successful transcript clears it.
            self.transcriptionError = "Reached the \(Int(AudioCapture.maxRecordingSeconds / 60))-minute recording limit. Transcribing what was captured."
        }
    }

    /// Invoked (on an arbitrary thread) when the audio engine's configuration
    /// changes mid-recording — a device being unplugged, a newly plugged-in device
    /// becoming default, or a sample-rate change. All invalidate the running tap,
    /// so stop cleanly and surface the reason. No auto-restart in this phase.
    private func handleInputConfigurationChange() {
        Task { @MainActor [weak self] in
            guard let self, self.state == .recording else { return }
            if self.isLiveSession {
                fputs("[DictationEngine] Audio input changed during live session — stopping.\n", stderr)
                self.audioCapture.onSamples = nil
                _ = self.audioCapture.stopRecording()
                self.soundFeedback.playStopSound()
                self.recordingStartTime = nil
                self.state = .processing        // consumer's finish returns to idle
                self.teardownLiveSession()      // residual discarded; committed text remains
                self.transcriptionError = "Audio input changed. Recording stopped."
                return
            }
            fputs("[DictationEngine] Audio input configuration changed during recording — stopping.\n", stderr)
            _ = self.audioCapture.stopRecording()
            self.soundFeedback.playStopSound()
            self.recordingStartTime = nil
            self.returnToIdle()
            self.transcriptionError = "Audio input changed. Recording stopped."
        }
    }
}

/// Accumulates corrected transcript segments during a streaming transcription.
/// Appended to only from the whisper decode queue (segment callbacks are delivered
/// serially) and read once after the transcribe `await` returns, which happens-after
/// all appends. That ordering makes the unsynchronized access sound; hence
/// `@unchecked Sendable`.
///
/// The live consumer extends that ordering rather than breaking it: one collector is
/// shared across a session's sequential decodes, and its reads (`text` for the next
/// chunk's prompt tail and the finish block; `atSentenceStart` inside a later decode's
/// segment callback) are still never concurrent with a write. Each `await transcribe`
/// in the single consumer loop is a happens-after edge over that decode's whisper-queue
/// writes, and the next decode — the only other writer — starts only after that await
/// returns. So at any instant exactly one thread touches `text`.
final class TranscriptCollector: @unchecked Sendable {
    private(set) var text: String = ""

    /// True when the next appended segment begins a sentence: nothing has
    /// been collected yet, or the collected text ends in terminal punctuation.
    var atSentenceStart: Bool {
        guard let last = text.last else { return true }
        return ".!?".contains(last)
    }

    /// Returns `segment` as it should be typed — with a leading space when
    /// joining onto already-collected text — and appends that same piece to
    /// `text`, so the typed stream and the collected transcript cannot drift.
    /// The separator is applied AFTER correction: the corrector trims leading
    /// whitespace, so a pre-correction separator would be eaten.
    func joinAndAppend(_ segment: String) -> String {
        let piece = text.isEmpty ? segment : " " + segment
        text += piece
        return piece
    }
}
