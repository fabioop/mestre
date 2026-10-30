import AppKit
import Quartz

/// Owns the shared Quick Look panel: one previewer for the whole app, so providers
/// don't fight over its data source. Focus goes back to the previous app on close.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()

    private var url: URL?
    private var previousApp: NSRunningApplication?

    func show(_ url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        self.url = url
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { url as NSURL? }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool { false }

    /// Called by the panel when it closes.
    func windowWillClose(_ notification: Notification) {
        previousApp?.activate()
    }
}
