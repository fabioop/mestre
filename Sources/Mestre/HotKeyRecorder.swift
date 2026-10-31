import AppKit
import Carbon.HIToolbox
import MestreCore
import SwiftUI

/// A button that, once clicked, captures the next key combination pressed.
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo
    @Binding var isRecording: Bool
    /// Keys inside the panel may be plain (↑, ⇥); a global shortcut needs a modifier.
    var allowsBareKeys = false

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView(combo: combo)
        view.allowsBareKeys = allowsBareKeys
        view.onRecordingChange = { recording in
            // Hop off the responder-chain callback before touching SwiftUI state.
            DispatchQueue.main.async { isRecording = recording }
        }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        // Refreshed every update: a caller's binding can capture the row as it was drawn.
        view.onChange = { combo = $0 }
        if view.combo != combo { view.combo = combo }
    }
}

extension HotKeyRecorder {
    /// A fixed size, centred on the row: an AppKit view has no text baseline for a form to
    /// line its label up with, and the row grows trying.
    func sized(width: CGFloat, height: CGFloat = 24) -> some View {
        frame(width: width, height: height)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
    }
}

final class RecorderView: NSView {
    var combo: KeyCombo { didSet { needsDisplay = true } }
    var allowsBareKeys = false
    var onChange: ((KeyCombo) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private(set) var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            onRecordingChange?(isRecording)
            needsDisplay = true
        }
    }

    init(combo: KeyCombo) {
        self.combo = combo
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            handle(event)
        } else if Int(event.keyCode) == kVK_Space || Int(event.keyCode) == kVK_Return {
            startRecording()
        } else {
            super.keyDown(with: event)
        }
    }

    /// Only on request. Recording switches every global hotkey off, so being handed focus when
    /// a window opens must not start it.
    private func startRecording() {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    /// AppKit doesn't resign a view that leaves its window (another page, a closed window), and
    /// a window that stops being key keeps its first responder. Either way the hotkeys come back.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        }
        if newWindow == nil {
            isRecording = false
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: newWindow)
        }
    }

    @objc private func windowDidResignKey() {
        isRecording = false
    }

    // ⌘-combinations arrive here before keyDown; swallow them while recording.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        handle(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        needsDisplay = true
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        if Int(event.keyCode) == kVK_Escape && modifiers.isEmpty {
            stopRecording()
            return
        }
        // A bare letter would hijack normal typing, system-wide or in the search field; require
        // a modifier unless it is a function key, or in the panel any key that doesn't type.
        let code = Int(event.keyCode)
        guard !modifiers.isEmpty || KeyCombo.functionKeyCodes.contains(code) || (allowsBareKeys && !KeyCombo.typesText(keyCode: code)) else {
            NSSound.beep()
            return
        }
        // No modifiers applied, so ⇧1 is "1": Shift's symbols can't be read back as a key.
        guard let recorded = KeyCombo.recorded(keyCode: event.keyCode, modifiers: modifiers, characters: event.characters(byApplyingModifiers: [])) else {
            NSSound.beep()
            return
        }
        combo = recorded
        onChange?(recorded)
        stopRecording()
    }

    private func stopRecording() {
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        let text = isRecording ? "Type shortcut…" : combo == .unset ? "Record Shortcut" : combo.displayString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}
