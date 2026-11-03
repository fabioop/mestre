import AppKit

/// ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z and ⇧⌘Z for text fields. A regular app gets them from its Edit menu;
/// Mestre shows no menu bar, so the panel maps them itself and the Settings window gets a
/// hidden Edit menu built from the same table.
enum EditShortcut {
    private struct Entry {
        let title: String
        let action: Selector
        let key: String
        var modifiers: NSEvent.ModifierFlags = .command
    }

    private static let entries = [
        Entry(title: "Undo", action: Selector(("undo:")), key: "z"),
        Entry(title: "Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift]),
        Entry(title: "Cut", action: #selector(NSText.cut(_:)), key: "x"),
        Entry(title: "Copy", action: #selector(NSText.copy(_:)), key: "c"),
        Entry(title: "Paste", action: #selector(NSText.paste(_:)), key: "v"),
        Entry(title: "Select All", action: #selector(NSText.selectAll(_:)), key: "a"),
    ]

    static func action(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        return entries.first { $0.key == key && $0.modifiers == modifiers }?.action
    }

    /// The menu bar of an app that shows none: only there so key equivalents reach the
    /// Settings window's fields.
    static func installMainMenu() {
        let edit = NSMenu(title: "Edit")
        for entry in entries {
            edit.addItem(withTitle: entry.title, action: entry.action, keyEquivalent: entry.key).keyEquivalentModifierMask = entry.modifiers
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem(title: "Mestre", action: nil, keyEquivalent: ""))
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
