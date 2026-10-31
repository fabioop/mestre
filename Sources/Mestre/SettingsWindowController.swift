import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: ConfigStore, viewModel: SearchViewModel, expander: TextExpander) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            // Full-size content lets the sidebar run up behind the traffic lights, its corners
            // following the window's, instead of floating under a separate title bar.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mestre Settings"
        window.isReleasedWhenClosed = false
        // A controller, not a bare view: it gives the split view the window's toolbar to share.
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, viewModel: viewModel, expander: expander))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 780, height: 560))
        // With no sizing options the view's own minimum doesn't reach the window.
        window.contentMinSize = NSSize(width: 760, height: 560)
        window.toolbar = NSToolbar(identifier: "settings")
        window.toolbarStyle = .unified
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
