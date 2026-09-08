import AppKit
import CoreGraphics
import Foundation

/// @unchecked Sendable: the only stored state is an immutable `CGEventSource?` and
/// a serial `DispatchQueue`. All typing runs on that queue; no mutable shared state.
final class TextInjector: @unchecked Sendable {
    private let source: CGEventSource?
    private let typingQueue = DispatchQueue(label: "com.lyra.typing", qos: .userInteractive)

    init() {
        source = CGEventSource(stateID: .combinedSessionState)
    }

    /// Enqueue `text` to be injected at the current cursor position.
    /// Default method uses universal clipboard paste (Cmd+V) with smart clipboard restoration,
    /// which works reliably across all applications (Chromium, Electron, WebKit, Safari,
    /// Telegram, Word, Terminal, Xcode) without dropping Cyrillic or Unicode characters.
    func type(text: String) {
        guard !text.isEmpty else { return }
        typingQueue.async { [weak self, source] in
            guard let self else { return }
            if AppSettings.shared.textInsertionMethod == .keystrokes {
                self.injectViaKeystrokes(text: text, source: source)
            } else {
                self.injectViaPasteboard(text: text, source: source)
            }
        }
    }

    /// Universal injection via NSPasteboard and synthesized Cmd+V.
    private func injectViaPasteboard(text: String, source: CGEventSource?) {
        fputs("[TextInjector] Pasting via pasteboard (\(text.count) chars): \"\(text.prefix(40))\"\n", stderr)

        let pasteboard = NSPasteboard.general

        // 1. Snapshot previous clipboard items to avoid losing user's clipboard
        let previousItems = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var dict = [NSPasteboard.PasteboardType: Data]()
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict.isEmpty ? nil : dict
        }

        // 2. Set new text on pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Give the pasteboard subsystem a moment to commit data
        Thread.sleep(forTimeInterval: 0.02)

        // 3. Synthesize Command+V
        // Virtual key 55 is Left Command (kVK_Command)
        // Virtual key 9 is 'V' (kVK_ANSI_V)
        guard let src = source ?? CGEventSource(stateID: .combinedSessionState) else {
            fputs("[TextInjector] Failed to create CGEventSource\n", stderr)
            return
        }

        let cmdKeyCode: CGKeyCode = 55
        let vKeyCode: CGKeyCode = 9

        guard let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmdKeyCode, keyDown: false) else {
            fputs("[TextInjector] Failed to create CGEvent for paste\n", stderr)
            return
        }

        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = []

        cmdDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.015)
        vDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.015)
        vUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.015)
        cmdUp.post(tap: .cghidEventTap)

        fputs("[TextInjector] Cmd+V posted successfully\n", stderr)

        // 4. Restore previous clipboard after target application has processed the paste
        if let previousItems, !previousItems.isEmpty {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.45) {
                // Only restore if user hasn't copied anything new in the meantime
                if pasteboard.string(forType: .string) == text {
                    pasteboard.clearContents()
                    for itemDict in previousItems {
                        let item = NSPasteboardItem()
                        for (type, data) in itemDict {
                            item.setData(data, forType: type)
                        }
                        pasteboard.writeObjects([item])
                    }
                }
            }
        }
    }

    /// Keystroke simulation using chunks of UTF-16 code units.
    private func injectViaKeystrokes(text: String, source: CGEventSource?) {
        let chunks = Self.chunks(of: Array(text.utf16))
        fputs("[TextInjector] Typing via keystrokes \(chunks.count) chunk(s) for \(text.count) characters\n", stderr)

        for (i, chunk) in chunks.enumerated() {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                fputs("[TextInjector] Failed to create CGEvent for chunk \(i)\n", stderr)
                continue
            }

            chunk.withUnsafeBufferPointer { ptr in
                keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: ptr.baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: ptr.baseAddress)
            }

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            if i < chunks.count - 1 {
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
    }

    /// Split a UTF-16 buffer into chunks of at most `maxChunk` code units for
    /// `keyboardSetUnicodeString`, **never splitting a surrogate pair across a chunk
    /// boundary**. A split pair would post a lone high surrogate followed by a lone low
    /// surrogate, which macOS renders as replacement characters instead of the intended
    /// emoji/astral glyph. Pure and static so the boundary math is unit-testable
    /// without CGEvent.
    static func chunks(of utf16: [UInt16], maxChunk: Int = 32) -> [[UInt16]] {
        guard maxChunk > 0 else { return utf16.isEmpty ? [] : [utf16] }
        var result: [[UInt16]] = []
        var offset = 0
        while offset < utf16.count {
            var end = min(offset + maxChunk, utf16.count)
            // If the last unit of this chunk is a high surrogate and a unit follows it
            // (its low surrogate), the pair straddles the boundary — back off by one so
            // the whole pair lands in the next chunk. The `end - 1 > offset` guard keeps
            // the chunk non-empty so progress is guaranteed even for pathological input.
            if end < utf16.count, Self.isHighSurrogate(utf16[end - 1]), end - 1 > offset {
                end -= 1
            }
            result.append(Array(utf16[offset..<end]))
            offset = end
        }
        return result
    }

    private static func isHighSurrogate(_ unit: UInt16) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }

    /// Barrier that blocks the caller until all previously-enqueued typing has
    /// finished. Because `typingQueue` is serial, a `sync {}` submitted after all the
    /// `async` type() work runs only once that work drains. MUST NOT be called on the
    /// main actor (it blocks). Intended to be called once, from the detached
    /// transcription task, before the done sound / return to idle.
    func flush() {
        typingQueue.sync {}
    }
}
