import AppKit
import SwiftUI

/// The search box, as a plain NSTextField for reliable first-responder handling.
/// Navigation keys never reach it: `SearchPanel.sendEvent` consumes anything bound
/// in the config's `keys` section before the field editor sees it.
struct QueryField: NSViewRepresentable {
    static let defaultPlaceholder = "Search apps, or pick a feature below…"
    @Binding var text: String
    var focusToken: Int
    let font: NSFont
    var placeholder = QueryField.defaultPlaceholder
    /// Nil keeps the system's colours.
    var textColor: NSColor?
    var placeholderColor: NSColor?
    var caretColor: NSColor?

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        context.coordinator.defaultTextColor = field.textColor
        applyPlaceholder(to: field, coordinator: context.coordinator)
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
        if field.font != font { field.font = font }
        let color = textColor ?? context.coordinator.defaultTextColor
        if field.textColor != color { field.textColor = color }
        applyPlaceholder(to: field, coordinator: context.coordinator)
        applyCaret(to: field)
        if field.stringValue != text {
            field.stringValue = text
            // Programmatic replacement (completion): put the caret at the end.
            field.currentEditor()?.selectedRange = NSRange(location: text.utf16.count, length: 0)
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { [caretColor] in
                field.window?.makeFirstResponder(field)
                // The editor exists only now; on a dark field the default caret can't be seen.
                if let caretColor { (field.currentEditor() as? NSTextView)?.insertionPointColor = caretColor }
            }
        }
    }

    /// Runs on every update, so it does nothing unless the text, colour or font changed.
    private func applyPlaceholder(to field: NSTextField, coordinator: Coordinator) {
        let key = Coordinator.PlaceholderKey(text: placeholder, color: placeholderColor, font: font)
        guard coordinator.placeholderKey != key else { return }
        coordinator.placeholderKey = key
        if let placeholderColor {
            field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.foregroundColor: placeholderColor, .font: font])
        } else {
            field.placeholderAttributedString = nil
            field.placeholderString = placeholder
        }
    }

    private func applyCaret(to field: NSTextField) {
        guard let editor = field.currentEditor() as? NSTextView else { return }
        let color = caretColor ?? .textInsertionPointColor
        if editor.insertionPointColor != color { editor.insertionPointColor = color }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QueryField
        var focusToken = 0
        var defaultTextColor: NSColor?

        struct PlaceholderKey: Equatable {
            let text: String
            let color: NSColor?
            let font: NSFont
        }
        var placeholderKey: PlaceholderKey?

        init(parent: QueryField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}
