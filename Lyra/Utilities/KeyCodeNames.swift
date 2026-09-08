import Foundation
import Carbon.HIToolbox

/// Single source of truth for hotkey keycode → human-readable labels.
///
/// Three presentations (descriptive, pill, short) are derived from one table so the
/// Settings recorder keycap, the quick-pick preset pills, and the menu-bar status
/// line can never drift apart. Previously each of the three sites maintained its own
/// hand-written keycode → name map.
enum KeyCodeNames {
    struct Key {
        let code: Int
        /// Modifier glyph, e.g. "⌥"; empty for keys without one (Fn).
        let symbol: String
        /// "Left"/"Right"; empty for single (non-sided) keys.
        let side: String
        /// Base name, e.g. "Option", "Caps Lock", "Fn".
        let name: String

        /// Long form for the recorder keycap: "⌥  Right Option", "Fn", "⇪  Caps Lock".
        var descriptive: String {
            let head = symbol.isEmpty ? "" : "\(symbol)  "
            let mid = side.isEmpty ? "" : "\(side) "
            return head + mid + name
        }

        /// Medium form for the quick-pick pills: "Right ⌥", "Fn".
        var pill: String {
            side.isEmpty ? name : "\(side) \(symbol)"
        }

        /// Short form for the menu-bar status line: "R⌥", "Fn", "⇪".
        var short: String {
            if side.isEmpty { return symbol.isEmpty ? name : symbol }
            return "\(side.prefix(1))\(symbol)"
        }
    }

    /// All keycodes the app can label. Superset of the three former maps. Modifier
    /// keys plus the common bindable non-modifier keys (Return/Space/Escape/Tab/Caps).
    static let all: [Key] = [
        Key(code: 54, symbol: "⌘", side: "Right", name: "Command"),
        Key(code: 55, symbol: "⌘", side: "Left",  name: "Command"),
        Key(code: 56, symbol: "⇧", side: "Left",  name: "Shift"),
        Key(code: 57, symbol: "⇪", side: "",      name: "Caps Lock"),
        Key(code: 58, symbol: "⌥", side: "Left",  name: "Option"),
        Key(code: 59, symbol: "⌃", side: "Left",  name: "Control"),
        Key(code: 60, symbol: "⇧", side: "Right", name: "Shift"),
        Key(code: 61, symbol: "⌥", side: "Right", name: "Option"),
        Key(code: 62, symbol: "⌃", side: "Right", name: "Control"),
        Key(code: 63, symbol: "",  side: "",      name: "Fn"),
        Key(code: 36, symbol: "↩", side: "",      name: "Return"),
        Key(code: 48, symbol: "⇥", side: "",      name: "Tab"),
        Key(code: 49, symbol: "␣", side: "",      name: "Space"),
        Key(code: 53, symbol: "⎋", side: "",      name: "Escape"),
        Key(code: 51, symbol: "⌫", side: "",      name: "Delete"),
        // Function keys. UCKeyTranslate returns nothing for these, so without an
        // entry here they would render as the "key" placeholder.
        Key(code: 122, symbol: "", side: "", name: "F1"),
        Key(code: 120, symbol: "", side: "", name: "F2"),
        Key(code: 99,  symbol: "", side: "", name: "F3"),
        Key(code: 118, symbol: "", side: "", name: "F4"),
        Key(code: 96,  symbol: "", side: "", name: "F5"),
        Key(code: 97,  symbol: "", side: "", name: "F6"),
        Key(code: 98,  symbol: "", side: "", name: "F7"),
        Key(code: 100, symbol: "", side: "", name: "F8"),
        Key(code: 101, symbol: "", side: "", name: "F9"),
        Key(code: 109, symbol: "", side: "", name: "F10"),
        Key(code: 103, symbol: "", side: "", name: "F11"),
        Key(code: 111, symbol: "", side: "", name: "F12"),
    ]

    private static let byCode: [Int: Key] = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    /// Keycodes macOS reports through `flagsChanged` (modifier keys), as opposed to
    /// `keyDown`/`keyUp`. Single source for the modifier classification that was
    /// duplicated in HotkeyMonitor and the Settings recorder.
    static let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    static func isModifier(_ code: Int) -> Bool { modifierKeyCodes.contains(code) }

    /// Ordered quick-pick pills for the recorder: Right⌥, Left⌥, Right⌃, Left⌃, Fn.
    static let presets: [Key] = [61, 58, 62, 59, 63].compactMap { byCode[$0] }

    /// Short label for the menu-bar status line. Codes outside the table (any
    /// ordinary letter, digit or punctuation key that can now take part in a
    /// combination) are resolved against the live keyboard layout.
    static func shortLabel(for code: Int) -> String {
        if let key = byCode[code] { return key.short }
        return layoutLabel(for: code) ?? "key"
    }

    /// Descriptive label for the recorder keycap. Unknown codes use `layoutFallback`
    /// (defaulting to the live keyboard-layout translation), then "Key <code>".
    static func descriptiveLabel(for code: Int, layoutFallback: (Int) -> String? = layoutLabel) -> String {
        if let key = byCode[code] { return key.descriptive }
        return layoutFallback(code) ?? "Key \(code)"
    }

    /// Translates a virtual keycode into the character it produces on the user's
    /// current keyboard layout, e.g. 50 -> "`". Shared by the recorder keycap and
    /// the status lines so a combination reads the same everywhere.
    static func layoutLabel(for code: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
        let layout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(
            layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
            UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState, chars.count, &length, &chars
        )
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length)
        return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : text.uppercased()
    }
}
