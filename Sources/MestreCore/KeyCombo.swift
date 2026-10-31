import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: a hardware-independent virtual key code plus modifier flags.
/// Stored as raw values so it is Codable and Sendable.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifierRawValue: UInt
    /// Human-readable name of the key (e.g. "Space", "K", "F5"), captured when recorded.
    public var keyLabel: String

    public static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// ⌥Space: avoids Spotlight's ⌘Space until the user turns that shortcut off.
    public static let `default` = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: .option, keyLabel: "Space")

    public init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        self.modifierRawValue = modifiers.intersection(Self.relevantModifiers).rawValue
        self.keyLabel = keyLabel
    }

    public var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    /// Modifier bits in the form Carbon's RegisterEventHotKey expects.
    public var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    /// Mac-style rendering in the conventional modifier order: ⌃⌥⇧⌘.
    public var displayString: String {
        var text = ""
        if modifiers.isSuperset(of: [.command, .option, .control, .shift]) { return "Hyper+" + keyLabel }
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyLabel
    }

    /// ⌘Space: Spotlight's shortcut, which macOS keeps until it is turned off there.
    public static let spotlight = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: .command, keyLabel: "Space")

    /// Whether Spotlight still answers to its shortcut, from the `AppleSymbolicHotKeys` value of
    /// `com.apple.symbolichotkeys`. Hotkey 64 is Spotlight; a Mac that never changed it has no entry.
    public static func spotlightHasShortcut(symbolicHotKeys: [String: Any]?) -> Bool {
        (symbolicHotKeys?["64"] as? [String: Any])?["enabled"] as? Bool ?? true
    }

    /// That value with Spotlight's shortcut switched, keeping whatever key it has. A Mac with no
    /// entry gets the one macOS assumes: Space (ASCII 32, key 49) with ⌘ (1 << 20).
    public static func spotlightHotKeys(_ symbolicHotKeys: [String: Any]?, enabled: Bool) -> [String: Any] {
        var all = symbolicHotKeys ?? [:]
        var entry = all["64"] as? [String: Any] ?? ["value": ["parameters": [32, 49, 1_048_576], "type": "standard"] as [String: Any]]
        entry["enabled"] = enabled
        all["64"] = entry
        return all
    }

    /// A recorder with nothing in it yet.
    public static let unset = KeyCombo(keyCode: 0, modifiers: [], keyLabel: "")

    public static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    /// A key that types into the search field unless a modifier is held, so it can't be a panel key alone.
    public static func typesText(keyCode: Int) -> Bool {
        specialKeyLabels[keyCode] == nil || keyCode == kVK_Space
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// Label for a key as the user pressed it. `characters` should be the event's
    /// `charactersIgnoringModifiers` so ⌥S is shown as "S", not "ß".
    public static func label(forKeyCode keyCode: UInt16, characters: String?) -> String {
        if let special = specialKeyLabels[Int(keyCode)] { return special }
        if let characters, !characters.isEmpty { return characters.uppercased() }
        return "Key \(keyCode)"
    }
}

// MARK: - Config file form ("option+space", "cmd+shift+k")

public extension KeyCombo {
    private static let namedKeys: [String: (code: Int, label: String)] = [
        "space": (kVK_Space, "Space"), "return": (kVK_Return, "↩"), "enter": (kVK_Return, "↩"),
        "tab": (kVK_Tab, "⇥"), "escape": (kVK_Escape, "⎋"), "esc": (kVK_Escape, "⎋"),
        "delete": (kVK_Delete, "⌫"), "backspace": (kVK_Delete, "⌫"), "forwarddelete": (kVK_ForwardDelete, "⌦"),
        "up": (kVK_UpArrow, "↑"), "down": (kVK_DownArrow, "↓"), "left": (kVK_LeftArrow, "←"), "right": (kVK_RightArrow, "→"),
        "home": (kVK_Home, "↖"), "end": (kVK_End, "↘"), "pageup": (kVK_PageUp, "⇞"), "pagedown": (kVK_PageDown, "⇟"),
        "f1": (kVK_F1, "F1"), "f2": (kVK_F2, "F2"), "f3": (kVK_F3, "F3"), "f4": (kVK_F4, "F4"), "f5": (kVK_F5, "F5"),
        "f6": (kVK_F6, "F6"), "f7": (kVK_F7, "F7"), "f8": (kVK_F8, "F8"), "f9": (kVK_F9, "F9"), "f10": (kVK_F10, "F10"),
        "f11": (kVK_F11, "F11"), "f12": (kVK_F12, "F12"), "f13": (kVK_F13, "F13"), "f14": (kVK_F14, "F14"),
        "f15": (kVK_F15, "F15"), "f16": (kVK_F16, "F16"), "f17": (kVK_F17, "F17"), "f18": (kVK_F18, "F18"),
        "f19": (kVK_F19, "F19"), "f20": (kVK_F20, "F20"),
    ]

    /// Canonical config name for a key code, used when writing the file.
    private static let canonicalNames: [Int: String] = {
        var names: [Int: String] = [:]
        for (name, key) in namedKeys where names[key.code] == nil || name.count < names[key.code]!.count {
            names[key.code] = name
        }
        // Prefer the long, unambiguous spellings.
        names[kVK_Return] = "return"; names[kVK_Escape] = "escape"; names[kVK_Delete] = "delete"
        return names
    }()

    /// Parses "option+space", "cmd+shift+k", "ctrl+opt+f5", "hyper+t". Modifier spellings: cmd/command,
    /// opt/option/alt, ctrl/control, shift, hyper (all four, the usual Caps Lock remap).
    /// Single characters resolve through the current keyboard layout.
    init?(parsing text: String, keyCodes: [Character: UInt16] = KeyCodeMap.current()) {
        var modifiers: NSEvent.ModifierFlags = []
        var keyName: String?
        for rawPart in text.lowercased().split(separator: "+") {
            let part = rawPart.trimmingCharacters(in: .whitespaces)
            switch part {
            case "cmd", "command", "⌘": modifiers.insert(.command)
            case "opt", "option", "alt", "⌥": modifiers.insert(.option)
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            case "shift", "⇧": modifiers.insert(.shift)
            case "hyper": modifiers.formUnion([.command, .option, .control, .shift])
            default:
                guard keyName == nil, !part.isEmpty else { return nil }
                keyName = part
            }
        }
        // "+" is the separator too, so "ctrl+option++" leaves no part for the key itself.
        if keyName == nil, text == "+" || text.hasSuffix("++") { keyName = "+" }
        guard let keyName else { return nil }

        if let named = Self.namedKeys[keyName] {
            self.init(keyCode: UInt32(named.code), modifiers: modifiers, keyLabel: named.label)
        } else if keyName.count == 1, let code = keyCodes[keyName.first!] {
            self.init(keyCode: UInt32(code), modifiers: modifiers, keyLabel: keyName.uppercased())
        } else if keyName.hasPrefix("key"), let code = UInt32(keyName.dropFirst(3)), code < 128 {
            self.init(keyCode: code, modifiers: modifiers, keyLabel: "Key \(code)")
        } else {
            return nil
        }
    }

    /// What a recorder keeps for a key press, or nil when the file couldn't read it back as the
    /// same key. `characters` should have no modifiers applied, so ⇧1 is "1" and not "!".
    static func recorded(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?, keyCodes: [Character: UInt16] = KeyCodeMap.current()) -> KeyCombo? {
        let combo = KeyCombo(keyCode: UInt32(keyCode), modifiers: modifiers, keyLabel: label(forKeyCode: keyCode, characters: characters))
        return combo.readsBack(keyCodes: keyCodes) ? combo : nil
    }

    /// The config stores the spelling, so it must parse back to the same key on this layout.
    func readsBack(keyCodes: [Character: UInt16] = KeyCodeMap.current()) -> Bool {
        KeyCombo(parsing: configString, keyCodes: keyCodes)?.keyCode == keyCode
    }

    /// The same physical key and modifiers, however each was spelled.
    func isSameKey(as other: KeyCombo) -> Bool {
        keyCode == other.keyCode && modifierRawValue == other.modifierRawValue
    }

    /// A key with no character of its own (a dead key) is written by its code: "key30".
    private var keyName: String {
        if let name = Self.canonicalNames[Int(keyCode)] { return name }
        return keyLabel.hasPrefix("Key ") ? "key\(keyCode)" : keyLabel.lowercased()
    }

    /// The form written to the config file, e.g. "option+space".
    var configString: String {
        var parts: [String] = []
        if modifiers.isSuperset(of: [.command, .option, .control, .shift]) {
            return "hyper+" + keyName
        }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }
}
