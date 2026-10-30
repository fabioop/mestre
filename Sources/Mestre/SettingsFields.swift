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
    var trailing = false
    var suffix: String? = nil

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if let label {
                LabeledContent(label) { control }
            } else {
                control
            }
        }
        .onAppear { text = render(value) }
        .onDisappear(perform: commit)
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onChange(of: value) { _, new in if parse(text) != new { text = render(new) } }
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
            HStack(spacing: 4) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(trailing ? .trailing : .leading)
                    .frame(width: width)
                    .focused($focused)
                    .onSubmit(commit)
                if let suffix { Text(suffix).foregroundStyle(.secondary) }
            }
        }
    }

    private func commit() {
        if let parsed = parse(text) {
            if parsed != value { value = parsed }
            text = render(parsed)
        } else {
            text = render(value)
        }
    }
}

/// Integer or floating-point value, clamped to `min`…`max`; non-finite input reverts.
struct NumberField<Value: Numeric & LosslessStringConvertible & Comparable>: View {
    let label: String
    @Binding var value: Value
    var suffix: String? = nil
    var min: Value? = nil
    var max: Value? = nil

    var body: some View {
        CommittedField(label: label, value: $value, render: { String($0) }, parse: parse, width: 80, trailing: true, suffix: suffix)
    }

    private func parse(_ text: String) -> Value? {
        guard var number = Value(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        if let double = number as? Double, !double.isFinite { return nil }
        if let min { number = Swift.max(min, number) }
        if let max { number = Swift.min(max, number) }
        return number
    }
}

/// Single line of text.
struct StringField: View {
    let label: String
    @Binding var value: String
    var placeholder = ""

    var body: some View {
        CommittedField(label: label, value: $value, render: { $0 }, parse: { $0 }, placeholder: placeholder, width: 220)
    }
}

/// A list of strings, one per line; blank lines are dropped.
struct StringListField: View {
    let label: String
    @Binding var values: [String]
    var placeholder = ""

    var body: some View {
        CommittedField(label: label, value: $values, render: { $0.joined(separator: "\n") }, parse: Self.parse, placeholder: placeholder, multiline: true)
    }

    static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// `[String: String]` as `key = value` lines. The separator is the first " = " (so a key may
/// contain "=", as in "hyper+="), falling back to the first "=".
struct StringMapField: View {
    let label: String
    @Binding var values: [String: String]
    var placeholder = "key = value"

    var body: some View {
        CommittedField(label: label, value: $values, render: Self.render, parse: Self.parse, placeholder: placeholder, multiline: true)
    }

    static func render(_ map: [String: String]) -> String {
        map.sorted(by: { $0.key < $1.key }).map { "\($0.key) = \($0.value)" }.joined(separator: "\n")
    }

    static func parse(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let split = line.range(of: " = ").map { ($0.lowerBound, $0.upperBound) }
                ?? line.firstIndex(of: "=").map { ($0, line.index(after: $0)) }
            guard let (keyEnd, valueStart) = split else { continue }
            let key = line[..<keyEnd].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { map[key] = line[valueStart...].trimmingCharacters(in: .whitespaces) }
        }
        return map
    }
}

/// Slider that writes to the config when the knob is released, not on every tick.
struct CommittedSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    @State private var local = 0.0

    var body: some View {
        LabeledContent(label) {
            Slider(value: $local, in: range, step: step) { editing in if !editing { value = local } }
                .frame(width: 170)
        }
        .onAppear { local = value }
        .onChange(of: value) { _, new in local = new }
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
                    Button {
                        items.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
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
