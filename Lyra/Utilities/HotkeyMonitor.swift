import Cocoa
import CoreGraphics
import os

/// Which binding fired. The primary key follows the user's dictation mode; the
/// hands-free key always toggles a hands-free session regardless of that mode.
enum HotkeyRole: CaseIterable {
    case primary
    case handsFree
}

final class HotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelfPtr: UnsafeMutableRawPointer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onKeyDown: (HotkeyRole) -> Void
    private let onKeyUp: (HotkeyRole) -> Void
    /// Fired when the hotkey turns out to be part of a system chord (e.g. the
    /// user pressed Option+Left, not Option alone). The engine must discard the
    /// recording that `onKeyDown` optimistically started.
    private let onChordAbort: () -> Void
    private let lock = os_unfair_lock_t.allocate(capacity: 1)

    private func binding(for role: HotkeyRole) -> HotkeyBinding {
        switch role {
        case .primary:   return AppSettings.shared.primaryHotkey
        case .handsFree: return AppSettings.shared.handsFreeHotkey
        }
    }

    private var monitoredKeyCode: CGKeyCode {
        CGKeyCode(max(0, AppSettings.shared.hotkeyKeyCode))
    }

    /// True when the primary binding is a lone modifier, which is the only shape
    /// that is matched through flagsChanged and subject to chord-abort.
    private var primaryIsBareModifier: Bool {
        AppSettings.shared.primaryHotkey.isBareModifier
    }

    private var heldRoles: Set<HotkeyRole> = []
    /// True once another key was pressed while a bare-modifier hotkey was down,
    /// so the current press is a system chord and never a dictation gesture.
    private var isChordInProgress = false

    init(
        onKeyDown: @escaping (HotkeyRole) -> Void,
        onKeyUp: @escaping (HotkeyRole) -> Void,
        onChordAbort: @escaping () -> Void = {}
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onChordAbort = onChordAbort
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        stop()
        lock.deallocate()
    }

    func start() {
        startNSEventMonitors()

        guard eventTap == nil else { return }
        let primary = AppSettings.shared.primaryHotkey
        let handsFree = AppSettings.shared.handsFreeHotkey
        fputs("[HotkeyMonitor] Starting... primary=\(primary.keyCode)/\(primary.modifierFlags) bareModifier=\(primary.isBareModifier) handsFree=\(handsFree.keyCode)/\(handsFree.modifierFlags)\n", stderr)

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleEvent(type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let eventTap else {
            fputs("[HotkeyMonitor] Event tap not yet active (waiting for Accessibility). NSEvent monitor active.\n", stderr)
            Unmanaged<HotkeyMonitor>.fromOpaque(selfPtr).release()
            return
        }

        fputs("[HotkeyMonitor] Event tap created successfully\n", stderr)
        retainedSelfPtr = selfPtr

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        // Watchdog: macOS silently disables taps when Accessibility permission is stale.
        // Schedule explicitly on main run loop to guarantee it fires.
        startTapWatchdog()
    }

    private var watchdogTimer: Timer?

    private func startTapWatchdog() {
        watchdogTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                fputs("[HotkeyMonitor] Event tap was disabled by macOS! Re-enabling...\n", stderr)
                CGEvent.tapEnable(tap: tap, enable: true)
                os_unfair_lock_lock(self.lock)
                let stuck = self.heldRoles
                self.heldRoles.removeAll()
                os_unfair_lock_unlock(self.lock)
                for role in stuck {
                    DispatchQueue.main.async { self.onKeyUp(role) }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func startNSEventMonitors() {
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
                self?.handleNSEvent(event)
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
                self?.handleNSEvent(event)
                return event
            }
        }
    }

    private func stopNSEventMonitors() {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
    }

    func stop() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        stopNSEventMonitors()

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
        if let ptr = retainedSelfPtr {
            Unmanaged<HotkeyMonitor>.fromOpaque(ptr).release()
            retainedSelfPtr = nil
        }
    }

    private func handleKeyStateChange(isPressed: Bool, role: HotkeyRole = .primary) {
        os_unfair_lock_lock(lock)
        let wasHeld = heldRoles.contains(role)
        if isPressed && !wasHeld {
            heldRoles.insert(role)
            isChordInProgress = false
            os_unfair_lock_unlock(lock)
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown(role)
            }
        } else if !isPressed && wasHeld {
            heldRoles.remove(role)
            // A chord already aborted the gesture on the first companion
            // keystroke; releasing the modifier must not then be read as the
            // short "tap" that latches hands-free recording.
            let wasChord = isChordInProgress
            isChordInProgress = false
            os_unfair_lock_unlock(lock)
            guard !wasChord else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp(role)
            }
        } else {
            os_unfair_lock_unlock(lock)
        }
    }

    /// Called when a key other than the monitored modifier is pressed. If the
    /// modifier is currently held, this press is a chord (Option+Left, Option+
    /// Delete, ⌥⇧V, dead-key accents, …) — cancel the dictation that keyDown
    /// started and latch the chord flag until the modifier is released.
    private func noteCompanionKeyPress() {
        // Only meaningful for a bare-modifier binding. When the user has
        // deliberately bound a chord (fn + `), a companion keystroke IS the
        // hotkey, and aborting on it would make the binding impossible to use.
        guard primaryIsBareModifier else { return }
        os_unfair_lock_lock(lock)
        guard heldRoles.contains(.primary), !isChordInProgress else {
            os_unfair_lock_unlock(lock)
            return
        }
        isChordInProgress = true
        os_unfair_lock_unlock(lock)
        DispatchQueue.main.async { [weak self] in
            self?.onChordAbort()
        }
    }

    private func handleNSEvent(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        // NSEvent.ModifierFlags and CGEventFlags share raw values for every bit
        // HotkeyBinding compares, so the same mask works for both paths.
        let rawFlags = UInt64(event.modifierFlags.rawValue)

        for role in HotkeyRole.allCases {
            let binding = self.binding(for: role)
            guard binding.isAssigned, !binding.isBareModifier, binding.keyCode == keyCode else { continue }
            if event.type == .keyDown, binding.matches(rawFlags: rawFlags) {
                handleKeyStateChange(isPressed: true, role: role)
                return
            }
            if event.type == .keyUp {
                handleKeyStateChange(isPressed: false, role: role)
                return
            }
        }

        for role in HotkeyRole.allCases {
            let binding = self.binding(for: role)
            guard binding.isBareModifier else { continue }
            if event.type == .flagsChanged,
               isTargetModifierKey(keyCode: CGKeyCode(keyCode), monitored: binding.keyCode) {
                let isPressed = isModifierPressed(CGEventFlags(rawValue: rawFlags), monitored: binding.keyCode)
                handleKeyStateChange(isPressed: isPressed, role: role)
                return
            }
        }

        if event.type == .keyDown || event.type == .flagsChanged {
            noteCompanionKeyPress()
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let rawFlags = event.flags.rawValue

        // Chord and plain-key bindings are matched first: they name an exact
        // key, so they are more specific than a generic bare-modifier binding.
        // They are swallowed, otherwise the key would also type its character.
        for role in HotkeyRole.allCases {
            let binding = self.binding(for: role)
            guard binding.isAssigned, !binding.isBareModifier, binding.keyCode == keyCode else { continue }
            if type == .keyDown, binding.matches(rawFlags: rawFlags) {
                handleKeyStateChange(isPressed: true, role: role)
                return nil
            }
            if type == .keyUp {
                var wasHeld = false
                os_unfair_lock_lock(lock)
                wasHeld = heldRoles.contains(role)
                os_unfair_lock_unlock(lock)
                if wasHeld {
                    handleKeyStateChange(isPressed: false, role: role)
                    return nil
                }
            }
        }

        // Bare-modifier bindings, matched through flagsChanged.
        for role in HotkeyRole.allCases {
            let binding = self.binding(for: role)
            guard binding.isBareModifier else { continue }
            if type == .flagsChanged, isTargetModifierKey(keyCode: CGKeyCode(keyCode), monitored: binding.keyCode) {
                let isPressed = isModifierPressed(event.flags, monitored: binding.keyCode)
                handleKeyStateChange(isPressed: isPressed, role: role)
                // Never swallow a bare modifier. Option/Command/Shift/Control
                // drive word-wise navigation, deletion, accent entry and every
                // system shortcut; consuming the event breaks all of them
                // system-wide while Lyra runs.
                return Unmanaged.passRetained(event)
            }
        }

        if type == .keyDown || type == .flagsChanged {
            noteCompanionKeyPress()
        }

        return Unmanaged.passRetained(event)
    }

    private func isTargetModifierKey(keyCode: CGKeyCode, monitored: Int) -> Bool {
        let actual = Int(keyCode)
        switch monitored {
        case 58, 61: // Option (Left or Right)
            return actual == 58 || actual == 61
        case 54, 55: // Command (Left or Right)
            return actual == 54 || actual == 55
        case 56, 60: // Shift (Left or Right)
            return actual == 56 || actual == 60
        case 59, 62: // Control (Left or Right)
            return actual == 59 || actual == 62
        case 57:     // Caps Lock
            return actual == 57
        case 63:     // Fn
            return actual == 63
        default:
            return actual == monitored
        }
    }

    private func isModifierPressed(_ flags: CGEventFlags, monitored: Int) -> Bool {
        switch monitored {
        case 58, 61: return flags.contains(.maskAlternate)
        case 59, 62: return flags.contains(.maskControl)
        case 56, 60: return flags.contains(.maskShift)
        case 54, 55: return flags.contains(.maskCommand)
        case 57:     return flags.contains(.maskAlphaShift)
        case 63:     return flags.contains(.maskSecondaryFn)
        default:     return false
        }
    }
}
