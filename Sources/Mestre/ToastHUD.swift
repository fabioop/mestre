import AppKit

/// A short message near the bottom of the screen, where `Feedback.toast` goes when the footer
/// can't show it: Copy Text from Screen's result, what a script printed, why a script failed.
/// Up to three wrapped lines. Never takes focus or clicks.
@MainActor
enum ToastHUD {
    private static var window: (panel: NSPanel, label: NSTextField)?
    /// Bumped per message so an older fade-out leaves a newer message alone.
    private static var generation = 0
    private static let maxWidth: CGFloat = 480
    private static let padding = NSSize(width: 18, height: 10)

    static func show(_ text: String, seconds: Double) {
        guard seconds > 0, !text.isEmpty else { return }
        let (panel, label) = window ?? makePanel()
        window = (panel, label)
        label.stringValue = text
        let fitted = label.sizeThatFits(NSSize(width: maxWidth - padding.width * 2, height: 200))
        let size = NSSize(width: min(maxWidth, ceil(fitted.width) + padding.width * 2), height: ceil(fitted.height) + padding.height * 2)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.15, width: size.width, height: size.height), display: false)
        }
        label.frame = NSRect(x: padding.width, y: padding.height, width: size.width - padding.width * 2, height: ceil(fitted.height))
        // Through the animator, so a fade-out still running for the last message stops here.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()

        generation &+= 1
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard generation == shown else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
                MainActor.assumeIsolated { if generation == shown { panel.orderOut(nil) } }
            }
        }
    }

    private static func makePanel() -> (NSPanel, NSTextField) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 3
        label.cell?.wraps = true
        background.addSubview(label)
        panel.contentView = background
        return (panel, label)
    }
}
