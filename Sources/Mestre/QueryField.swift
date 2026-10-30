import AppKit
import SwiftUI

/// The search box, as a plain NSTextField for reliable first-responder handling.
/// Navigation keys never reach it: `SearchPanel.sendEvent` consumes anything bound
/// in the config's `keys` section before the field editor sees it.
struct QueryField: NSViewRepresentable {
    static let defaultPlaceholder = "Search apps, or pick a feature below…"
    @Binding var text: String
    var focusToken: Int
    let fontSize: Double
    var placeholder = QueryField.defaultPlaceholder

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.font?.pointSize != CGFloat(fontSize) { field.font = .systemFont(ofSize: fontSize) }
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        if field.stringValue != text {
            field.stringValue = text
            // Programmatic replacement (completion): put the caret at the end.
            field.currentEditor()?.selectedRange = NSRange(location: text.utf16.count, length: 0)
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QueryField
        var focusToken = 0

        init(parent: QueryField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}
