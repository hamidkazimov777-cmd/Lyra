import Cocoa
import ApplicationServices

/// Safe and fast reader for currently selected text in whatever application is active.
/// Uses macOS Accessibility APIs (kAXSelectedTextAttribute) with zero clipboard disruption.
final class SelectedTextReader {

    /// Queries the focused element in the frontmost application for any selected text.
    /// Returns nil if nothing is selected or if accessibility is not permitted.
    static func getSelectedText() -> String? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.08)

        var focusedAppRef: CFTypeRef?
        let appError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )

        guard appError == .success, let focusedApp = focusedAppRef else {
            return nil
        }

        // AXUIElementCopyAttributeValue hands back an untyped CFTypeRef. A
        // misbehaving app returning something else would crash a force cast, so
        // check the CFTypeID before trusting it.
        guard CFGetTypeID(focusedApp) == AXUIElementGetTypeID() else { return nil }
        let appElement = focusedApp as! AXUIElement
        AXUIElementSetMessagingTimeout(appElement, 0.08)

        var focusedElementRef: CFTypeRef?
        let elemError = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard elemError == .success, let focusedElement = focusedElementRef else {
            return nil
        }

        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return nil }
        let uiElement = focusedElement as! AXUIElement
        AXUIElementSetMessagingTimeout(uiElement, 0.08)

        var selectedTextRef: CFTypeRef?
        let textError = AXUIElementCopyAttributeValue(
            uiElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )

        if textError == .success, let selectedText = selectedTextRef as? String {
            let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                fputs("[SelectedTextReader] Captured selected text (\(trimmed.count) chars)\n", stderr)
                return trimmed
            }
        }

        return nil
    }
}
