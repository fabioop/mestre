import AppKit
import ApplicationServices
import Carbon.HIToolbox
import MestreCore

/// Puts text in front of the user: on the pasteboard and, with Accessibility access,
/// pasted into the frontmost app with ⌘V. Shared by clipboard history and snippets.
@MainActor
final class Paster {
    var settings = Config.Paste()
    private let clipboard: ClipboardMonitor

    init(clipboard: ClipboardMonitor) { self.clipboard = clipboard }

    /// Posting keyboard events needs the Accessibility permission.
    nonisolated static var canPaste: Bool { AXIsProcessTrusted() }

    /// Records any pending copy first, then puts `text` on the pasteboard without
    /// recording it, closes the panel (`dismiss`) and pastes. `caretMoves` Left presses
    /// follow, for a snippet's `{cursor}`.
    func paste(_ text: String, caretMoves: Int = 0, dismiss: (() -> Void)?) {
        clipboard.captureNow()
        clipboard.write(text)
        dismiss?()
        sendPaste(caretMoves: caretMoves)
    }

    /// Pasteboard only, no ⌘V.
    func copy(_ text: String, dismiss: (() -> Void)?) {
        clipboard.captureNow()
        clipboard.write(text)
        dismiss?()
    }

    /// Same, for a history entry (any kind).
    func paste(_ entry: ClipboardEntry, dismiss: (() -> Void)?) {
        clipboard.copy(entry)
        dismiss?()
        sendPaste(caretMoves: 0)
    }

    private func sendPaste(caretMoves: Int) {
        guard Self.canPaste, let keyCode = KeyCodeMap.current()["v"] else { return }
        let delay = settings.delaySeconds
        let caretDelay = settings.cursorDelaySeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Self.press(CGKeyCode(keyCode), flags: .maskCommand)
            guard caretMoves > 0 else { return }
            // The paste has to land before the caret moves; slow apps need a longer cursorDelaySeconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + caretDelay) {
                for _ in 0..<caretMoves { Self.press(CGKeyCode(kVK_LeftArrow), flags: []) }
            }
        }
    }

    /// Marks events Mestre posts, so the text-expansion tap ignores them.
    static let ownEventTag: Int64 = 0x4D535452

    /// One tagged key press, no modifiers unless given.
    static func press(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: ownEventTag)
            event.post(tap: .cghidEventTap)
        }
    }
}

extension ItemAction {
    static let paste = ItemAction(id: "paste", title: "Paste", icon: "arrow.down.doc")
    static let copy = ItemAction(id: "copy", title: "Copy", icon: "doc.on.doc")
    /// Both, for the action table; `pasteOrCopy` picks at run time.
    static let pasteAndCopy = [paste, copy]
}

extension Array where Element == ItemAction {
    /// Paste first when ⌘V can be sent, otherwise Copy; `extra` follows.
    static func pasteOrCopy(extra: [ItemAction] = []) -> [ItemAction] {
        (Paster.canPaste ? [.paste, .copy] : [.copy]) + extra
    }
}
