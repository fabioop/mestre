import AppKit

/// A modal yes/no question. Mestre is an accessory app, so it comes forward for the alert and
/// hands focus back to the app the user was in when the answer is no, and with `refocusAfter`
/// also when it is yes (a script that acts on the frontmost app).
@MainActor
enum Confirmation {
    static func ask(_ message: String, detail: String, button: String, refocusAfter: Bool = false) -> Bool {
        let previous = NSWorkspace.shared.frontmostApplication
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if !confirmed || refocusAfter { previous?.activate() }
        return confirmed
    }
}
