import Cocoa
import CoreGraphics
import os

final class HotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelfPtr: UnsafeMutableRawPointer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void
    private let lock = os_unfair_lock_t.allocate(capacity: 1)

    private var monitoredKeyCode: CGKeyCode {
        CGKeyCode(AppSettings.shared.hotkeyKeyCode)
    }

    private var isModifierKey: Bool {
        KeyCodeNames.isModifier(Int(monitoredKeyCode))
    }

    private var isKeyHeld = false

    init(onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        stop()
        lock.deallocate()
    }

    func start() {
        startNSEventMonitors()

        guard eventTap == nil else { return }
        fputs("[HotkeyMonitor] Starting... keyCode=\(monitoredKeyCode) isModifier=\(isModifierKey)\n", stderr)

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
                let wasHeld = self.isKeyHeld
                self.isKeyHeld = false
                os_unfair_lock_unlock(self.lock)
                if wasHeld {
                    DispatchQueue.main.async { self.onKeyUp() }
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

    private func handleKeyStateChange(isPressed: Bool) {
        os_unfair_lock_lock(lock)
        let wasHeld = isKeyHeld
        if isPressed && !wasHeld {
            isKeyHeld = true
            os_unfair_lock_unlock(lock)
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown()
            }
        } else if !isPressed && wasHeld {
            isKeyHeld = false
            os_unfair_lock_unlock(lock)
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp()
            }
        } else {
            os_unfair_lock_unlock(lock)
        }
    }

    private func handleNSEvent(_ event: NSEvent) {
        let keyCode = CGKeyCode(event.keyCode)
        if isModifierKey {
            if event.type == .flagsChanged && isTargetModifierKey(keyCode: keyCode) {
                let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                let isPressed = isModifierPressed(flags)
                handleKeyStateChange(isPressed: isPressed)
            }
        } else {
            if keyCode == monitoredKeyCode {
                if event.type == .keyDown {
                    handleKeyStateChange(isPressed: true)
                } else if event.type == .keyUp {
                    handleKeyStateChange(isPressed: false)
                }
            }
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if isModifierKey {
            if type == .flagsChanged && isTargetModifierKey(keyCode: keyCode) {
                let flags = event.flags
                let isPressed = isModifierPressed(flags)
                handleKeyStateChange(isPressed: isPressed)
                return nil
            }
        } else {
            if keyCode == monitoredKeyCode {
                if type == .keyDown {
                    handleKeyStateChange(isPressed: true)
                    return nil
                } else if type == .keyUp {
                    handleKeyStateChange(isPressed: false)
                    return nil
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func isTargetModifierKey(keyCode: CGKeyCode) -> Bool {
        let monitored = Int(monitoredKeyCode)
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

    private func isModifierPressed(_ flags: CGEventFlags) -> Bool {
        let code = Int(monitoredKeyCode)
        switch code {
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
