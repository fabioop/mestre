import AppKit
import ApplicationServices
import MestreCore

/// The Accessibility permission, shared by every feature that needs it (window layouts, open
/// windows, paste, menu search). Checking never prompts; only `requestAccess` does, and only
/// from a user's action on a feature that needs it, never at launch.
enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (once: macOS remembers the answer) and returns whether access is granted.
    @discardableResult
    static func prompt() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    static func openSettings() {
        NSWorkspace.shared.open(SettingsPane.privacyURL("Privacy_Accessibility"))
    }

    /// The prompt, then System Settings › Accessibility when access is still missing, since the
    /// prompt shows only the first time.
    static func requestAccess() {
        if !prompt() { openSettings() }
    }
}
