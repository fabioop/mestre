import AppKit
import Carbon.HIToolbox
import MestreCore
import SwiftUI

/// A button that, once clicked, captures the next key combination pressed.
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView(combo: combo)
        view.onChange = { combo = $0 }
        view.onRecordingChange = { recording in
            // Hop off the responder-chain callback before touching SwiftUI state.
            DispatchQueue.main.async { isRecording = recording }
        }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        if view.combo != combo { view.combo = combo }
    }
}

final class RecorderView: NSView {
    var combo: KeyCombo { didSet { needsDisplay = true } }
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

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        handle(event)
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
        // A bare letter would hijack normal typing system-wide; require a modifier
        // unless it is a function key.
        guard !modifiers.isEmpty || KeyCombo.functionKeyCodes.contains(Int(event.keyCode)) else {
            NSSound.beep()
            return
        }
        let label = KeyCombo.label(forKeyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
        combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
        onChange?(combo)
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

        let text = isRecording ? "Type shortcut…" : combo.displayString
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
