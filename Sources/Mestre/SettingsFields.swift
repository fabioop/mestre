import SwiftUI

// Editors for config values. Text reaches the config only when committed (Return, focus
// loss, or the view going away), so a half-typed value never hits the file or the search
// results, and ConfigStore's save-and-reload echo can't rewrite text under the cursor.

/// Generic committed editor: `render` shows the value, `parse` turns text back into one
/// (nil reverts the text). Single-line fields submit on Return; multiline ones use a text
/// editor where Return inserts a line.
struct CommittedField<Value: Equatable>: View {
    var label: String? = nil
    @Binding var value: Value
    let render: (Value) -> String
    let parse: (String) -> Value?
    var placeholder = ""
    var width: CGFloat? = nil
    var multiline = false

    @State private var text = ""
    /// The text as last taken from or given to the value; anything else was typed.
    @State private var synced = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if let label {
                LabeledContent(label) { control }
            } else {
                control
            }
        }
        .onAppear { sync(to: value) }
        // Only what was typed: the change that removes a field never reaches onChange below, so
        // its text can be out of date and would overwrite the new value.
        .onDisappear { if text != synced { commit() } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onChange(of: value) { _, new in if parse(text) != new { sync(to: new) } }
    }

    @ViewBuilder private var control: some View {
        if multiline {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: width ?? 260, maxWidth: width ?? 260, minHeight: 56)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty { Text(placeholder).foregroundStyle(.tertiary).padding(.leading, 5).padding(.top, 1).allowsHitTesting(false) }
                }
                .focused($focused)
        } else {
            // A form would draw the title as a second label beside the field.
            TextField("", text: $text, prompt: Text(placeholder))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: width)
                .focused($focused)
                .onSubmit(commit)
                .accessibilityLabel(label ?? placeholder)
        }
    }

    private func commit() {
        if let parsed = parse(text) {
            if parsed != value { value = parsed }
            sync(to: parsed)
        } else {
            sync(to: value)
        }
    }

    private func sync(to value: Value) {
        text = render(value)
        synced = text
    }
}

/// Editable rows for a list of named items (quicklinks, snippets). Rows get a binding to
/// their element plus a check for names already used by other rows, since both models are
/// identified by name and the config drops duplicates when it is re-read.
struct ItemListEditor<Item: Identifiable & Equatable, Row: View>: View where Item.ID == String {
    @Binding var items: [Item]
    let addTitle: String
    let template: (String) -> Item
    @ViewBuilder let row: (Binding<Item>, _ nameTaken: @escaping (String) -> Bool) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 6) {
                    row(binding(at: index)) { name in nameTaken(name, except: index) }
                    RemoveButton { items.remove(at: index) }
                }
            }
            Button(addTitle) { items.append(template(uniqueName())) }
        }
    }

    private func nameTaken(_ name: String, except index: Int) -> Bool {
        items.indices.contains { $0 != index && items[$0].id.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func uniqueName() -> String {
        let base = "New"
        var name = base, n = 1
        while nameTaken(name, except: -1) { n += 1; name = "\(base) \(n)" }
        return name
    }

    /// Guarded: a row can still be rendering while its element is removed.
    private func binding(at index: Int) -> Binding<Item> {
        Binding(
            get: { index < items.count ? items[index] : template("") },
            set: { if index < items.count { items[index] = $0 } }
        )
    }
}

/// Name and keyword cells shared by the quicklink and snippet rows. A name another row
/// already has is refused (the field reverts) so no row disappears on the next reload.
struct NameKeywordRow: View {
    @Binding var name: String
    @Binding var keyword: String?
    let nameTaken: (String) -> Bool
    var keywordPlaceholder = "keyword"

    var body: some View {
        HStack {
            CommittedField(value: $name, render: { $0 }, parse: { nameTaken($0) ? nil : $0 }, placeholder: "Name", width: 180)
            CommittedField(value: $keyword, render: { $0 ?? "" }, parse: { $0.isEmpty ? .some(nil) : .some($0) }, placeholder: keywordPlaceholder, width: 90)
        }
    }
}

/// Secondary explanatory text under a control.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

/// A problem with the current config, in red.
struct ErrorCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.red)
    }
}
