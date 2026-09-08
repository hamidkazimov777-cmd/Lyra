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
        self.hostingController = hostingController
        bindEngine()
        update()
    }

    private var hostingController: NSHostingController<DynamicIslandHUDView>?

    /// Re-measures the SwiftUI content and resizes the panel to match.
    ///
    /// `NSHostingController.sizingOptions` would do this automatically but is
    /// macOS 13+, and the app targets 12.0 — so the size is taken from
    /// `fittingSize` after a layout pass, driven by the same Combine
    /// subscription that already refreshes the HUD.
    /// Signature of everything that can change the island's size. The audio
    /// analyzer republishes ~30x a second to animate the waveform, but that never
    /// changes the layout — re-measuring on every tick would run a full SwiftUI
    /// layout pass at 30 fps for nothing.
    private var lastLayoutSignature: String = ""

    private func syncPanelSizeToContent() {
        guard let view = hostingController?.view else { return }

        let signature = [
            engine.state.rawValue,
            engine.liveTranscription,
            engine.previewTranscript,
            engine.lastTranscription,
            String(engine.isSmartEditActive),
            String(engine.isHandsFreeActive),
            String(engine.isFallbackActive),
            AppSettings.shared.selectedLanguage.rawValue
        ].joined(separator: "\u{1}")
        guard signature != lastLayoutSignature else { return }
        lastLayoutSignature = signature

        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        resizeToFit(size)
    }

    /// Resizes the panel around its top edge and horizontal centre, so a growing
    /// transcript expands downwards and outwards symmetrically the way the
    /// Dynamic Island does — rather than dragging the top-left corner around, as
    /// AppKit's bottom-left window origin would otherwise cause.
    private func resizeToFit(_ size: NSSize) {
        guard let panel else { return }
        let current = panel.frame
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else { return }

        // Vertically the island always grows downwards from its top edge.
        //
        // Horizontally it re-centres only when the user has never positioned it.
        // Re-centring an explicitly placed panel makes each resize move it by
        // half the size delta, and those errors compound across successive
        // resizes until the island walks into the edge of the screen.
        let anchorTop = current.maxY
        let hasUserPosition = AppSettings.shared.floatingWidgetPositionX != nil
        let newX = hasUserPosition ? current.origin.x : current.midX - size.width / 2
        var target = NSRect(
            x: newX,
            y: anchorTop - size.height,
            width: size.width,
            height: size.height
        )

        // Keep the island fully on its current screen as it grows.
        if let visible = Self.screen(containing: current)?.visibleFrame {
            target.origin.x = min(max(target.origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            target.origin.y = min(max(target.origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }

        lastProgrammaticOrigin = target.origin
        panel.setFrame(target, display: true, animate: false)
    }

    /// Origin of the most recent resize this class performed.
    ///
    /// `windowDidMove` cannot be suppressed with a flag around `setFrame`: the
    /// notification is delivered asynchronously, so the flag is already back to
    /// false by the time it arrives, and every resize was persisting itself as if
    /// the user had dragged the panel there. Comparing origins is delivery-order
    /// independent.
    private var lastProgrammaticOrigin: NSPoint?

    private static func screen(containing frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) } ?? activeScreen()
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
        syncPanelSizeToContent()
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

        // A resize moves the origin too, because the island is anchored by its
        // top edge. Persisting that would let the pinned position creep every
        // time the transcript grows or shrinks, so only record real user drags.
        if let programmatic = lastProgrammaticOrigin,
           abs(programmatic.x - origin.x) < 0.5, abs(programmatic.y - origin.y) < 0.5 {
            return
        }

        AppSettings.shared.floatingWidgetPositionX = origin.x
        AppSettings.shared.floatingWidgetPositionY = origin.y
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
