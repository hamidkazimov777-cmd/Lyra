import SwiftUI
import Carbon.HIToolbox

struct HotkeyRecorder: View {
    @Binding var binding: HotkeyBinding
    let colorScheme: ColorScheme
    /// Shows a clear button and accepts "no shortcut" — used by the optional
    /// hands-free key, which may legitimately be unassigned.
    var allowsUnassigned: Bool = false

    @State private var isRecording = false
    @State private var eventMonitors: [Any] = []
    /// Modifiers currently held during capture. A chord is committed when a
    /// normal key arrives; a lone modifier is committed when everything is
    /// released without one, so holding ⌥ on the way to ⌥K is not mistaken for
    /// a bare-⌥ binding.
    @State private var pendingFlags: UInt64 = 0
    @State private var pendingModifierKeyCode: Int = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Keycap display
            Button(action: { toggleRecording() }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                isRecording
                                    ? LinearGradient(colors: [.blue, .blue.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [Color.white.opacity(0.12), Color.white.opacity(0.06)]
                                            : [Color.white, Color(.controlBackgroundColor)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isRecording ? Color.blue.opacity(0.5) : (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 1, y: 1)
                            .frame(height: 38)

                        if isRecording {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 6, height: 6)
                                    .opacity(0.8)
                                Text(L10n.tr("Press any key..."))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        } else {
                            Text(binding.label(keyNameFallback: KeyCodeNames.layoutLabel))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(binding.isAssigned ? .primary : .secondary)
                        }
                    }

                    if !isRecording {
                        Text(L10n.tr("Click to change"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    if allowsUnassigned && binding.isAssigned && !isRecording {
                        Button(L10n.tr("Clear")) { binding = .unassigned }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                    }
                }
            }
            .buttonStyle(.plain)

            // Quick pick pills
            HStack(spacing: 6) {
                ForEach(KeyCodeNames.presets, id: \.code) { preset in
                    Button {
                        binding = HotkeyBinding(keyCode: preset.code, modifierFlags: 0)
                        stopRecording()
                    } label: {
                        Text(preset.pill)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(binding.keyCode == preset.code && binding.modifierFlags == 0
                                        ? Color.blue.opacity(0.15)
                                        : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(binding.keyCode == preset.code && binding.modifierFlags == 0 ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                            .foregroundStyle(binding.keyCode == preset.code && binding.modifierFlags == 0 ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        pendingFlags = 0
        pendingModifierKeyCode = -1

        // A normal key ends capture immediately, carrying whatever modifiers are
        // held with it — this is what makes `fn + \`` recordable.
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let flags = UInt64(event.modifierFlags.rawValue) & HotkeyBinding.relevantMask
            binding = HotkeyBinding(keyCode: Int(event.keyCode), modifierFlags: flags)
            stopRecording()
            return nil
        }

        let flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            let code = Int(event.keyCode)
            let flags = UInt64(event.modifierFlags.rawValue) & HotkeyBinding.relevantMask

            if flags != 0 {
                // Modifiers going down: remember them, but wait. Committing here
                // would capture ⌥ the instant it is pressed and make a chord
                // impossible to type.
                pendingFlags = flags
                if KeyCodeNames.isModifier(code) { pendingModifierKeyCode = code }
                return nil
            }

            // Everything released with no normal key in between: the user meant
            // the lone modifier itself.
            if let lone = pendingModifierKeyCode >= 0 ? pendingModifierKeyCode : nil {
                binding = HotkeyBinding(keyCode: lone, modifierFlags: 0)
                stopRecording()
            }
            return nil
        }

        if let keyMonitor { eventMonitors.append(keyMonitor) }
        if let flagsMonitor { eventMonitors.append(flagsMonitor) }
    }

    private func stopRecording() {
        isRecording = false
        pendingFlags = 0
        pendingModifierKeyCode = -1
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        eventMonitors.removeAll()
    }

}
