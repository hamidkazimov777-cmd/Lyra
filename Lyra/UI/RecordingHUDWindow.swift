import SwiftUI
import AppKit
import Combine

/// A non-activating floating panel that refuses key/main status so clicks on the
/// HUD never steal focus from the active text field.
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Container whose clickable area is limited to the island itself.
///
/// The panel is intentionally larger than the island so glow and growth are
/// never clipped by the window edge, which means most of it is transparent.
/// Without this, that transparent margin would swallow clicks meant for the app
/// underneath.
final class HUDContentView: NSView {
    /// Opaque region, in this view's coordinates. Anything outside it is
    /// transparent and must not intercept the mouse.
    var activeRect: NSRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard activeRect.contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// Manages the floating Dynamic Island HUD panel.
///
/// The panel has ONE fixed size for its whole lifetime. It used to re-measure
/// the SwiftUI content and resize itself on every update, which caused three
/// separate defects: shadows sliced off at the window edge, the island walking
/// across the screen as it was re-centred and clamped, and a resize →
/// `windowDidMove` → settings-write → resize feedback loop. The island now
/// animates inside a stable window and nothing here reacts to its contents.
final class RecordingHUDWindow: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var container: HUDContentView?
    private var cancellables = Set<AnyCancellable>()

    private let engine: DictationEngine
    private let analyzer: AudioLevelAnalyzer

    /// Last stage the hit region was built for, so the common case (a streamed
    /// transcript update) does no work at all.
    private var lastState: DictationState?

    init(engine: DictationEngine, analyzer: AudioLevelAnalyzer) {
        self.engine = engine
        self.analyzer = analyzer
        super.init()

        Self.migrateSavedPositionIfNeeded()

        let view = DynamicIslandHUDView(engine: engine, analyzer: analyzer)
        let hostingController = NSHostingController(rootView: view)

        let panelSize = HUDLayout.panelSize

        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let container = HUDContentView(frame: NSRect(origin: .zero, size: panelSize))
        container.autoresizingMask = [.width, .height]
        hostingController.view.frame = container.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        container.addSubview(hostingController.view)

        panel.contentView = container
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // Shadow is drawn by SwiftUI inside the island.
        panel.delegate = self
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        self.panel = panel
        self.container = container
        self.hostingController = hostingController

        positionAtSavedAnchorOrTopCenter()
        bindEngine()
        update()
    }

    private var hostingController: NSHostingController<DynamicIslandHUDView>?

    // MARK: - Position
    //
    // The saved position is the panel's TOP-LEFT corner rather than AppKit's
    // bottom-left origin. With a fixed panel size the two are interchangeable,
    // but storing the top edge keeps the island where the user put it if the
    // panel size is ever tuned again.

    private static let anchorVersionKey = "hudAnchorVersion"
    private static let currentAnchorVersion = 2

    /// One-time conversion of the pre-fixed-size position, which was a
    /// bottom-left origin of a panel that was about 72pt tall.
    private static func migrateSavedPositionIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: anchorVersionKey) < currentAnchorVersion else { return }
        defaults.set(currentAnchorVersion, forKey: anchorVersionKey)

        let settings = AppSettings.shared
        guard let y = settings.floatingWidgetPositionY else { return }
        settings.floatingWidgetPositionY = y + 72
    }

    private var savedAnchor: NSPoint? {
        let settings = AppSettings.shared
        guard let x = settings.floatingWidgetPositionX, let y = settings.floatingWidgetPositionY else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    /// Top-left point of the most recent move this class performed.
    ///
    /// `windowDidMove` is delivered asynchronously, so a "we are moving it
    /// ourselves" flag is already back to false by the time the notification
    /// arrives — every programmatic placement would then be persisted as if the
    /// user had dragged the panel there, pinning it on first show. Comparing
    /// points is delivery-order independent.
    private var lastProgrammaticAnchor: NSPoint?

    private func setAnchor(_ anchor: NSPoint) {
        lastProgrammaticAnchor = anchor
        panel?.setFrameTopLeftPoint(anchor)
    }

    private func positionAtSavedAnchorOrTopCenter() {
        guard panel != nil else { return }

        if let anchor = savedAnchor,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: NSPoint(x: anchor.x, y: anchor.y - HUDLayout.panelSize.height), size: HUDLayout.panelSize)) }) {
            setAnchor(anchor)
            return
        }

        if let screenFrame = Self.activeScreen()?.visibleFrame {
            let x = screenFrame.midX - HUDLayout.panelSize.width / 2
            setAnchor(NSPoint(x: x, y: screenFrame.maxY - 4))
        }
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

    // MARK: - Visibility

    func show() {
        guard let panel else { return }
        guard !panel.isVisible else { return }

        // With no pinned position, follow the user across displays rather than
        // reappearing on whichever screen the panel was last created on.
        if savedAnchor == nil {
            positionAtSavedAnchorOrTopCenter()
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
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
        // Deliberately NOT subscribed to `analyzer`: it republishes ~30x a
        // second to animate the waveform, and the SwiftUI view observes it
        // directly. Waking this class up on every audio frame is what turned a
        // cheap visualisation into a full AppKit layout pass at 30 fps.
        engine.objectWillChange
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
        syncHitRegion()

        let settings = AppSettings.shared
        let isRecording = engine.state != .idle
        let shouldBeVisible = settings.isFloatingWidgetAlwaysVisible || (isRecording && settings.showRecordingHUD)

        if shouldBeVisible {
            show()
        } else {
            hide()
        }
    }

    /// Keeps the clickable area in step with the island's current stage. Four
    /// discrete rectangles, recomputed only when the stage actually changes.
    private func syncHitRegion() {
        guard engine.state != lastState else { return }
        lastState = engine.state
        container?.activeRect = HUDLayout.hitRect(for: engine.state)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        let anchor = NSPoint(x: panel.frame.origin.x, y: panel.frame.maxY)

        // Only record real user drags: persisting our own placement would pin
        // the island on first show and stop it following the user's display.
        if let programmatic = lastProgrammaticAnchor,
           abs(programmatic.x - anchor.x) < 0.5, abs(programmatic.y - anchor.y) < 0.5 {
            return
        }

        AppSettings.shared.floatingWidgetPositionX = anchor.x
        AppSettings.shared.floatingWidgetPositionY = anchor.y
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
