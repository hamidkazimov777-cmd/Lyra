import SwiftUI
import AppKit
import Combine

/// A non-activating floating panel that refuses key/main status so clicks on the
/// HUD never steal focus from the active text field.
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Manages the floating Dynamic Island HUD panel.
/// Borderless, non-activating, and floats above other windows.
final class RecordingHUDWindow: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    private let engine: DictationEngine
    private let analyzer: AudioLevelAnalyzer

    init(engine: DictationEngine, analyzer: AudioLevelAnalyzer) {
        self.engine = engine
        self.analyzer = analyzer
        super.init()

        let view = DynamicIslandHUDView(engine: engine, analyzer: analyzer)
        let hostingController = NSHostingController(rootView: view)

        let panelWidth: CGFloat = 440
        let panelHeight: CGFloat = 72

        let panel = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // Shadow is cleanly handled by SwiftUI DynamicIslandHUDView
        panel.delegate = self
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        // Position: restore saved coordinates if they still land on a connected
        // display, otherwise top-center of the active screen.
        let settings = AppSettings.shared
        if let savedX = settings.floatingWidgetPositionX,
           let savedY = settings.floatingWidgetPositionY,
           NSScreen.screens.contains(where: { $0.visibleFrame.contains(CGPoint(x: savedX, y: savedY)) }) {
            panel.setFrameOrigin(NSPoint(x: savedX, y: savedY))
        } else if let screenFrame = Self.activeScreen()?.visibleFrame {
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.maxY - panelHeight - 12
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
        bindEngine()
        update()
    }

    /// The display the user is actually working on: the one under the pointer,
    /// falling back to the key window's screen, then `NSScreen.main`.
    ///
    /// `NSScreen.main` alone is wrong on multi-display setups — it is the screen
    /// with the key window, which on a docked laptop is regularly the closed lid
    /// or a side panel, putting the HUD nowhere near the user's attention.
    static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let underCursor = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return underCursor
        }
        return NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    func show() {
        // With no pinned position, follow the user across displays rather than
        // reappearing on whichever screen the panel was last created on.
        if AppSettings.shared.floatingWidgetPositionX == nil,
           let panel,
           let screenFrame = Self.activeScreen()?.visibleFrame {
            let x = screenFrame.midX - panel.frame.width / 2
            let y = screenFrame.maxY - panel.frame.height - 12
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        guard let panel else { return }
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Binding

    private func bindEngine() {
        engine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.update()
            }
            .store(in: &cancellables)

        analyzer.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.update()
            }
            .store(in: &cancellables)

        AppSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.update()
            }
            .store(in: &cancellables)
    }

    private func update() {
        let settings = AppSettings.shared
        let isRecording = engine.state != .idle
        let shouldBeVisible = settings.isFloatingWidgetAlwaysVisible || (isRecording && settings.showRecordingHUD)

        if shouldBeVisible {
            show()
        } else {
            hide()
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        let origin = panel.frame.origin
        AppSettings.shared.floatingWidgetPositionX = origin.x
        AppSettings.shared.floatingWidgetPositionY = origin.y
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
