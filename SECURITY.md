# Security Policy

## Threat Model

Lyra is a macOS dictation app that requires two sensitive permissions — **Microphone** and **Accessibility** — and, in its default configuration, sends audio and text to a **third-party cloud API**. This document describes exactly what leaves your Mac and what stays on it.

### Two operating modes

Lyra can run in either of two transcription modes, chosen in **Settings → Provider**:

| Mode | Where audio is processed | Network |
|---|---|---|
| **Cloud / Custom API** (default) | Your configured provider (OpenAI, Groq, OpenRouter, Google Gemini, or a local gateway such as Ollama/vLLM) | Audio is uploaded as a WAV to that provider's `/audio/transcriptions` endpoint |
| **Local Whisper** | Entirely on your Mac via whisper.cpp (Metal/CPU) | No audio leaves the device |

**Local Whisper mode is the only configuration in which no audio or text leaves your Mac.** If you need an offline guarantee, select it and turn off AI post-processing and Smart Voice Editing.

### Permissions

| Permission | What it's used for |
|-----------|-------------------|
| Microphone | Capture audio only while a dictation session is active (hotkey held, hands-free session running, or started from the HUD). Audio is buffered in RAM as 16 kHz mono Float32 and discarded when the session ends. Audio is never written to disk. |
| Accessibility | Detect the global hotkey via `CGEvent.tapCreate`; read the current selection via the Accessibility API when Smart Voice Editing is enabled; inject text at the cursor. Lyra does not log or transmit keystrokes. |

### What leaves your Mac

Be aware of each of the following. All are visible and controllable in Settings.

- **Audio → transcription provider.** In Cloud/Custom API mode, the recorded audio is uploaded to the Base URL you configured. Under the default preset that is a third party's servers, subject to *their* privacy policy and retention.
- **Text → AI provider.** When **AI post-processing** is enabled, the draft transcription is sent to the chat-completions endpoint configured under **Settings → Provider → AI Text Provider** (OpenRouter by default).
- **Selected text → AI provider.** When **Smart Voice Editing** is enabled and you dictate over a selection, both the selected text and your spoken instruction are sent to that same endpoint.
- **Model catalogue requests.** On launch Lyra queries the configured providers' `/models` endpoints to populate the model pickers.
- **Model downloads.** Whisper and voice-activity models are fetched from HuggingFace. Since 1.3.0 this happens **only** when Local Whisper is the selected provider or you click Download explicitly — never silently for cloud-only users.

Lyra performs **no** telemetry, analytics, crash reporting, auto-update checks, license checks, or account/"phone home" traffic of its own. Every outbound request goes to an endpoint you configured or a model file you asked for.

### What is stored on your Mac

- **API keys** are stored in the **macOS Keychain** (`kSecClassGenericPassword`, service `com.lyra.Lyra`, `kSecAttrAccessibleAfterFirstUnlock`, never synced to iCloud). Builds up to 1.2.2 stored them in plaintext `UserDefaults`; 1.3.0 migrates them into the Keychain on first launch and deletes the plaintext copy.
- **Dictation history** — up to 1000 recent transcriptions — is written to `~/Library/Application Support/Lyra/history.json` as **unencrypted JSON**, protected only by macOS file permissions. Turn this off with **Settings → Advanced → Private mode**, and clear existing entries from the History tab.
- **Preferences** live in `~/Library/Preferences/com.lyra.Lyra.plist` and contain no secrets.
- **Audio is never persisted.** Recorded samples exist only in memory for the duration of a session.

### Clipboard

The default text-insertion method is clipboard paste (`Cmd+V`), because it is the only approach that reliably handles Cyrillic and other non-Latin text across browsers, Electron apps and native software. This means Lyra **reads, temporarily overwrites and then restores** `NSPasteboard.general` on each insertion. If you would rather Lyra never touch the pasteboard, switch **Settings → Advanced → Text Insertion** to "Simulate Keystrokes".

### Key isolation

The speech endpoint and the AI-text endpoint are configured separately. Lyra sends the speech provider's API key to the AI endpoint **only** if you explicitly opt in *and* both endpoints resolve to the same host; on a host mismatch the key is withheld rather than transmitted. (Builds up to 1.2.2 sent the speech key to `openrouter.ai` unconditionally — if you used one of those builds with a non-OpenRouter key, rotate that key.)

## Auditability

Every network-facing line is greppable:

```bash
git clone https://github.com/hamidkazimov777-cmd/Lyra.git
cd Lyra
grep -rE "URLSession|URLRequest|http://|https://" --include='*.swift' Lyra/
```

The matches are confined to three files:

- `Lyra/Engine/OpenAISpeechService.swift` — transcription, model listing, AI post-processing and Smart Voice Editing requests, all sent to the Base URLs configured in Settings.
- `Lyra/Engine/ModelManager.swift` — HuggingFace URLs for Whisper and voice-activity model files.
- `Lyra/Utilities/AppInfo.swift` — static project links shown in the About screen.

To verify the offline claim for Local Whisper mode, select it, disable AI post-processing and Smart Voice Editing, and watch with a firewall such as [Little Snitch](https://www.obdev.at/products/littlesnitch/) or [LuLu](https://objective-see.org/products/lulu.html). In that configuration you will see zero outbound connections during dictation.

## Build from Source

Don't want to trust the pre-built DMG? Build from source:

```bash
git clone --recurse-submodules https://github.com/hamidkazimov777-cmd/Lyra.git
cd Lyra
make whisper && make app
open build/Lyra.app
```

The Makefile compiles directly via `xcrun swiftc` with no opaque build steps. You can read the entire pipeline in the [Makefile](Makefile).

## Dependencies

- **[whisper.cpp](https://github.com/ggerganov/whisper.cpp)** (git submodule) — C/C++ port of OpenAI Whisper. MIT licensed. Compiled as a static library, linked directly into the app. No dynamic libraries.
- **Whisper models** (downloaded on demand) — Pre-trained ML models from OpenAI, distributed via HuggingFace. MIT licensed.
- **macOS frameworks** (AVFoundation, Metal, CoreGraphics, AppKit, etc.) — First-party Apple frameworks.

No third-party Swift packages, no CocoaPods, no Carthage. The only external code is whisper.cpp and Apple's SDK.

## Code Signing

Releases are currently **ad-hoc signed** (not notarized by Apple). This means macOS Gatekeeper will show a warning on first launch. We document how to bypass this in the install instructions. Formal Developer ID notarization is planned once the project enrolls in the Apple Developer Program.

Every release DMG will include a SHA256 checksum in the release notes so you can verify integrity.

## Reporting a Vulnerability

If you discover a security issue, please **do not open a public issue**. Instead:

1. Email the maintainer directly (see [GitHub profile](https://github.com/hamidkazimov777-cmd)), or
2. Open a [private security advisory](https://github.com/hamidkazimov777-cmd/Lyra/security/advisories/new) on GitHub

We aim to respond within 72 hours. Critical issues will be patched and disclosed on an accelerated timeline.

## Scope

In scope:
- Network activity to any endpoint the user did not configure
- Transmission of credentials to a provider other than the one they were entered for
- Leakage of dictated text or audio outside the configured provider
- Privilege escalation via the Accessibility API
- Audio capture outside an active dictation session
- Insecure storage of API keys or history on disk
- Memory safety issues in our Swift code or bridging layer
- Supply chain concerns around whisper.cpp or model downloads

Out of scope:
- Vulnerabilities in whisper.cpp itself (please report to the [whisper.cpp project](https://github.com/ggerganov/whisper.cpp))
- Vulnerabilities in macOS or Apple frameworks
- Physical attacks requiring local user access

## Acknowledgments

Security researchers who responsibly disclose issues will be credited in release notes unless they prefer to remain anonymous.
