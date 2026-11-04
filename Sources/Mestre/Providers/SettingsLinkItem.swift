import AppKit
import MestreCore

/// A row whose only job is to send the user to System Settings: a permission to grant, an
/// account to add, a language to download.
struct SettingsLinkItem: SearchItem {
    let id: String
    let title: String
    let subtitle: String?
    let iconSymbol: String?
    let kind: ItemKind
    let action: ItemAction
    let url: URL

    var icon: NSImage? { nil }
    var actions: [ItemAction] { [action] }
}

extension ResultProvider {
    /// Opens a `SettingsLinkItem`'s pane; false for any other row.
    func openSettingsLink(_ item: any SearchItem) -> Bool {
        guard let link = item as? SettingsLinkItem else { return false }
        dismiss?()
        NSWorkspace.shared.open(link.url)
        return true
    }
}
