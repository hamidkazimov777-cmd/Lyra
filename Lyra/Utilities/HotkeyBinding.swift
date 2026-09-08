import Foundation
import CoreGraphics

/// A global shortcut: one key plus the modifiers that must be held with it.
///
/// The app used to store a hotkey as a bare `Int` keycode, which made chords
/// such as `fn + \`` unrepresentable — the recorder read `event.keyCode` and
/// discarded `event.modifierFlags`. Modelling the pair explicitly is what makes
/// combinations possible.
struct HotkeyBinding: Equatable, Hashable {
    /// Virtual keycode, or `-1` when the binding is unassigned.
    var keyCode: Int
    /// Required modifiers as an `NSEvent.ModifierFlags` / `CGEventFlags` raw
    /// value. The two types share raw values for every flag used here.
    var modifierFlags: UInt64

    static let unassigned = HotkeyBinding(keyCode: -1, modifierFlags: 0)

    /// Modifier bits the app compares on. Everything else reported by the system
    /// — device-dependent left/right bits, `maskNonCoalesced`, numeric-pad and
    /// help flags — is noise that would break equality checks.
    static let relevantMask: UInt64 =
        CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskShift.rawValue
        | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskSecondaryFn.rawValue

    var isAssigned: Bool { keyCode >= 0 }

    /// True for a lone modifier key with no other modifiers required (the
    /// classic "hold ⌥ to dictate" binding). These are matched through
    /// `flagsChanged`, are never swallowed, and are the only bindings that take
    /// part in chord-abort detection.
    var isBareModifier: Bool {
        modifierFlags & Self.relevantMask == 0 && KeyCodeNames.isModifier(keyCode)
    }

    /// True when the binding needs modifiers held alongside a normal key, e.g.
    /// `fn + \``. These are matched through `keyDown`/`keyUp` and are swallowed
    /// so the key does not also type its character.
    var isChord: Bool {
        isAssigned && modifierFlags & Self.relevantMask != 0
    }

    /// Whether an event's raw flags satisfy this binding. Exact match on the
    /// relevant bits, so `fn + \`` does not fire for `fn + ⇧ + \``.
    func matches(rawFlags: UInt64) -> Bool {
        rawFlags & Self.relevantMask == modifierFlags & Self.relevantMask
    }

    /// Compact label for status lines, e.g. "fn`" or "L⌥".
    var shortLabel: String {
        guard isAssigned else { return "—" }
        var prefix = ""
        let flags = modifierFlags & Self.relevantMask
        if flags & CGEventFlags.maskSecondaryFn.rawValue != 0 { prefix += "fn" }
        if flags & CGEventFlags.maskControl.rawValue != 0 { prefix += "⌃" }
        if flags & CGEventFlags.maskAlternate.rawValue != 0 { prefix += "⌥" }
        if flags & CGEventFlags.maskShift.rawValue != 0 { prefix += "⇧" }
        if flags & CGEventFlags.maskCommand.rawValue != 0 { prefix += "⌘" }
        return prefix + KeyCodeNames.shortLabel(for: keyCode)
    }

    /// Human-readable label, e.g. "fn  `" or "⌥  Left Option".
    func label(keyNameFallback: (Int) -> String?) -> String {
        guard isAssigned else { return "—" }
        var parts: [String] = []
        let flags = modifierFlags & Self.relevantMask
        if flags & CGEventFlags.maskSecondaryFn.rawValue != 0 { parts.append("fn") }
        if flags & CGEventFlags.maskControl.rawValue != 0 { parts.append("⌃") }
        if flags & CGEventFlags.maskAlternate.rawValue != 0 { parts.append("⌥") }
        if flags & CGEventFlags.maskShift.rawValue != 0 { parts.append("⇧") }
        if flags & CGEventFlags.maskCommand.rawValue != 0 { parts.append("⌘") }
        parts.append(KeyCodeNames.descriptiveLabel(for: keyCode, layoutFallback: keyNameFallback))
        return parts.joined(separator: "  ")
    }
}
