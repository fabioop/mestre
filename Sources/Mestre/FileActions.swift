import AppKit
import MestreCore

extension ItemAction {
    static let open = ItemAction(id: "open", title: "Open", icon: "doc")
    static let quickLook = ItemAction(id: "quickLook", title: "Quick Look", icon: "eye", defaultKeys: ["cmd+y"])
}

/// The actions every file-backed item shares: Open, Quick Look, Show in Finder, Copy Path.
@MainActor
enum FileActions {
    /// Returns true when it handled the action.
    static func perform(_ action: ItemAction, on url: URL, dismiss: (() -> Void)?) -> Bool {
        switch action.id {
        case ItemAction.open.id, "finder":
            dismiss?()
            NSWorkspace.shared.open(url)
        case ItemAction.quickLook.id:
            QuickLook.shared.show(url)
        case ItemAction.reveal.id:
            dismiss?()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case ItemAction.copyPath.id:
            url.path.copyToPasteboard(toast: "Path copied")
        default:
            return false
        }
        return true
    }
}

extension NSWorkspace {
    private static let iconCache = NSCache<NSString, NSImage>()

    /// A 32pt file icon, cached by path: the first lookup touches disk, the rest don't.
    func cachedIcon(forFile path: String) -> NSImage {
        if let cached = Self.iconCache.object(forKey: path as NSString) { return cached }
        let icon = self.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        Self.iconCache.setObject(icon, forKey: path as NSString)
        return icon
    }
}
