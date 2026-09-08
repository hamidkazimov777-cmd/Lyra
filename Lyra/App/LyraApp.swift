import SwiftUI
import AppKit
import Combine

@main
struct LyraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // macOS 12 requires at least one Scene. Settings is a valid scene type.
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    let audioLevelAnalyzer = AudioLevelAnalyzer()
    lazy var engine = DictationEngine(audioLevelAnalyzer: audioLevelAnalyzer)
    lazy var recordingHUD = RecordingHUDWindow(engine: engine, analyzer: audioLevelAnalyzer)

    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?

    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Move any API key written by a pre-Keychain build out of the plaintext
        // preferences plist before anything reads it.
        AppSettings.shared.migrateSecretsToKeychainIfNeeded()

        // Touching the store loads history.json, which also tightens the file's
        // permissions if an older build left it world-readable. It is loaded on
        // the first dictation regardless, so this only moves the work earlier.
        _ = HistoryStore.shared

        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        // MenuBarView drives window opening through NotificationCenter.
        popover.contentViewController = NSHostingController(rootView: MenuBarView(engine: engine))
        
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Lyra Dictation"
            
            updateStatusItemIcon()
            
            // Observe changes
            engine.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItemIcon()
                }
            }.store(in: &cancellables)
        }
        
        // Setup notification listeners for opening windows from SwiftUI
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: NSNotification.Name("OpenSettings"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openOnboarding), name: NSNotification.Name("OpenOnboarding"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(closePopover), name: NSNotification.Name("ClosePopover"), object: nil)

        // Initialize the recording HUD so it observes engine state.
        _ = recordingHUD

        // Auto-configure OpenRouter preset if not set
        let settings = AppSettings.shared
        if settings.apiPreset != .openRouter && settings.apiKey.isEmpty {
            settings.transcriptionProviderType = .api
            settings.apiPreset = .openRouter
            settings.apiBaseURL = APIPresetProvider.openRouter.defaultBaseURL
            settings.apiModelName = APIPresetProvider.openRouter.defaultModel
        }

        // Fetch OpenRouter models in background
        Task {
            let res = await TranscriptionCoordinator.shared.apiService.fetchAvailableModels(
                baseURLString: settings.apiBaseURL,
                apiKey: settings.apiKey
            )
            if res.success && !res.models.isEmpty {
                await MainActor.run {
                    settings.apiAvailableModels = res.models
                }
            }

            let postRes = await TranscriptionCoordinator.shared.apiService.fetchPostProcessingModels()
            if postRes.success && !postRes.models.isEmpty {
                await MainActor.run {
                    settings.aiPostProcessingAvailableModels = postRes.models
                }
            }
        }

        // If the user has no usable model for the current language (e.g. switched
        // language and the previous model is English-only), start the recommended
        // download automatically instead of leaving the app unable to transcribe.
        ModelManager.shared.ensureDownloadedRecommendedModel(for: AppSettings.shared.selectedLanguage)

        presentOnboardingIfNeeded()
    }
    
    @objc func statusItemClicked(_ sender: AnyObject?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
    
    @objc func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
    
    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        
        let isRec = engine.state == .recording
        let dictItem = NSMenuItem(
            title: isRec ? "Stop Dictation" : "Start Dictation (Hands-Free)",
            action: #selector(toggleDictationFromMenu),
            keyEquivalent: "d"
        )
        dictItem.target = self
        menu.addItem(dictItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let toggleHUDItem = NSMenuItem(
            title: AppSettings.shared.isFloatingWidgetAlwaysVisible ? "Hide Floating Pill" : "Show Floating Pill",
            action: #selector(toggleFloatingWidgetFromMenu),
            keyEquivalent: ""
        )
        toggleHUDItem.target = self
        menu.addItem(toggleHUDItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Lyra", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }
    
    @objc func toggleDictationFromMenu() {
        engine.toggleRecording()
    }
    
    @objc func toggleFloatingWidgetFromMenu() {
        AppSettings.shared.isFloatingWidgetAlwaysVisible.toggle()
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func updateStatusItemIcon() {
        guard let button = statusItem.button else { return }

        let tintColor: NSColor?
        if engine.isHoldingForToggle {
            tintColor = .systemOrange
        } else {
            switch engine.state {
            case .idle, .typing:
                tintColor = nil
            case .recording:
                tintColor = .systemRed
            case .processing:
                tintColor = .systemOrange
            }
        }

        // Try bundle resource first, then procedural drawing of Lyra constellation
        var image: NSImage? = Bundle.main.image(forResource: "MenuBarIcon") ?? NSImage(named: "MenuBarIcon")
        if image == nil {
            image = createDefaultMenuBarIcon()
        }

        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tintColor
        
        if button.image == nil {
            button.title = engine.state == .recording ? "🎙️ REC" : "✦ Lyra"
        } else {
            button.title = ""
        }
    }
    
    private func createDefaultMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)

            let s: CGFloat = 18.0
            let padX = s * (2.2 / 18.0)
            let padY = s * (2.8 / 18.0)
            let wUsable = s - 2 * padX
            let hUsable = s - 2 * padY

            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let nx = (x - 29.5) / 97.0
                let ny = (114.0 - y) / 80.5
                return CGPoint(x: padX + nx * wUsable, y: padY + ny * hUsable)
            }

            let pPeak = pt(110.0, 33.5)
            let pRight = pt(126.5, 48.0)
            let pJunc = pt(95.5, 63.0)
            let pTL = pt(51.0, 67.5)
            let pBL = pt(29.5, 114.0)
            let pBR = pt(64.0, 114.0)

            let stroke = s * (1.1 / 18.0)
            ctx.setLineWidth(stroke)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Triangle (Vega, epsilon, zeta)
            ctx.beginPath()
            ctx.move(to: pPeak)
            ctx.addLine(to: pRight)
            ctx.addLine(to: pJunc)
            ctx.closePath()
            ctx.strokePath()

            // Parallelogram (delta, zeta, gamma, beta)
            ctx.beginPath()
            ctx.move(to: pTL)
            ctx.addLine(to: pJunc)
            ctx.addLine(to: pBR)
            ctx.addLine(to: pBL)
            ctx.closePath()
            ctx.strokePath()

            // Stars
            let r = s * (0.95 / 18.0)
            let rVega = s * (1.35 / 18.0)
            func dot(_ p: CGPoint, rad: CGFloat) {
                ctx.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
            }
            dot(pPeak, rad: rVega)
            dot(pRight, rad: r)
            dot(pJunc, rad: r)
            dot(pTL, rad: r)
            dot(pBL, rad: r)
            dot(pBR, rad: r)

            return true
        }
        img.isTemplate = true
        return img
    }
    
    // MARK: - Windows
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(engine: engine)
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 520),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Lyra Settings"
            window.contentViewController = controller
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func openOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(engine: engine)
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to Lyra"
            window.contentViewController = controller
            window.center()
            window.isReleasedWhenClosed = false
            onboardingWindow = window
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func presentOnboardingIfNeeded() {
        let settings = AppSettings.shared
        guard !settings.hasCompletedOnboarding else { return }

        let hasAnyModel = !ModelManager.shared.downloadedModels().isEmpty
        if OnboardingView.shouldShowOnboarding(hasCompleted: settings.hasCompletedOnboarding, hasAnyModel: hasAnyModel) {
            openOnboarding()
        } else {
            settings.hasCompletedOnboarding = true
        }
    }
}
