import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: ConfigStore, viewModel: SearchViewModel, expander: TextExpander) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mestre Settings"
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: SettingsView(settings: settings, viewModel: viewModel, expander: expander))
        window.contentView = hosting
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

}

extension NSWindowController {
    /// An accessory app has to activate explicitly for a regular window to take focus.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
