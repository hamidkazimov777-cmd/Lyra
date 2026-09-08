import AppKit
import CoreGraphics
import Foundation

/// @unchecked Sendable: typing runs on a serial queue, and the clipboard
/// ownership state shared with the deferred restore is guarded by `clipboardLock`.
final class TextInjector: @unchecked Sendable {
    private let source: CGEventSource?
    private let typingQueue = DispatchQueue(label: "com.lyra.typing", qos: .userInteractive)

    // Clipboard ownership tracking, guarded by `clipboardLock` because the
    // restore runs on a global queue while injection runs on `typingQueue`.
    private let clipboardLock = NSLock()
    /// changeCount of the pasteboard write this injector made last, or -1.
    private var lastInjectedChangeCount: Int = -1
    /// The user's clipboard, held across back-to-back injections.
    private var pendingRestoreItems: [[NSPasteboard.PasteboardType: Data]]?

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
        // Content-bearing form is DEBUG-only: stderr from a bundled app is captured
        // by launchd into the unified log, where dictated text would persist in
        // Console.app beyond the user's reach — and would survive Private mode.
        #if DEBUG
        fputs("[TextInjector] Pasting via pasteboard (\(text.count) chars): \"\(text.prefix(40))\"\n", stderr)
        #else
        fputs("[TextInjector] Pasting via pasteboard (\(text.count) chars)\n", stderr)
        #endif

        let pasteboard = NSPasteboard.general

        // 1. Decide what to put back afterwards.
        //
        // If the board still holds the text *we* pasted last time, re-snapshotting
        // would capture Lyra's own output as "the user's clipboard" and restore
        // that instead. Two dictations inside the restore window used to destroy
        // the real clipboard exactly this way, so carry the original snapshot
        // forward rather than taking a new one.
        let previousItems: [[NSPasteboard.PasteboardType: Data]]?
        clipboardLock.lock()
        if Self.ownsClipboard(currentChangeCount: pasteboard.changeCount,
                              lastInjectedChangeCount: lastInjectedChangeCount) {
            previousItems = pendingRestoreItems
        } else {
            previousItems = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
                var dict = [NSPasteboard.PasteboardType: Data]()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        dict[type] = data
                    }
                }
                return dict.isEmpty ? nil : dict
            }
        }
        clipboardLock.unlock()

        // 2. Set new text on pasteboard. clearContents() returns the resulting
        // changeCount, which is our proof of ownership at restore time.
        let ownChangeCount = pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        clipboardLock.lock()
        lastInjectedChangeCount = ownChangeCount
        pendingRestoreItems = previousItems
        clipboardLock.unlock()

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

        // 4. Restore the user's clipboard once the target app has read the paste.
        //
        // The window is generous because slow Electron and remote-desktop targets
        // can take several hundred milliseconds to act on Cmd+V, and restoring
        // early makes them paste the wrong thing. Waiting longer is safe now that
        // the changeCount guard below aborts the restore the moment anything else
        // touches the board — including the user copying something.
        if let previousItems, !previousItems.isEmpty {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.clipboardRestoreDelay) { [weak self] in
                guard let self else { return }
                self.clipboardLock.lock()
                defer { self.clipboardLock.unlock() }

                // Someone changed the board after us (the user, or a later
                // injection that owns its own restore) — leave it alone.
                guard Self.shouldRestoreClipboard(currentChangeCount: pasteboard.changeCount,
                                                  ownedChangeCount: self.lastInjectedChangeCount) else { return }

                pasteboard.clearContents()
                for itemDict in previousItems {
                    let item = NSPasteboardItem()
                    for (type, data) in itemDict {
                        item.setData(data, forType: type)
                    }
                    pasteboard.writeObjects([item])
                }
                self.lastInjectedChangeCount = -1
                self.pendingRestoreItems = nil
            }
        }
    }

    /// How long to leave the dictated text on the clipboard before restoring.
    static let clipboardRestoreDelay: TimeInterval = 0.8

    /// True when the board still holds this injector's own last paste, meaning a
    /// fresh snapshot would capture Lyra's output instead of the user's
    /// clipboard and the earlier snapshot must be carried forward instead.
    /// Pure/static so the ownership math is unit-testable without NSPasteboard.
    static func ownsClipboard(currentChangeCount: Int, lastInjectedChangeCount: Int) -> Bool {
        lastInjectedChangeCount >= 0 && currentChangeCount == lastInjectedChangeCount
    }

    /// True when the deferred restore may proceed: only if nothing has touched
    /// the pasteboard since this injector wrote to it.
    static func shouldRestoreClipboard(currentChangeCount: Int, ownedChangeCount: Int) -> Bool {
        ownsClipboard(currentChangeCount: currentChangeCount, lastInjectedChangeCount: ownedChangeCount)
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
