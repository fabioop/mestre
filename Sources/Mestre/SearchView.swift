import MestreCore
import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: SearchViewModel

    static let headerHeight: CGFloat = 24
    private var layout: Config.Panel { viewModel.layout }
    private var accent: Color { viewModel.accent }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: layout.queryFontSize * 0.8, weight: .medium))  // icon tracks the query font
                    .foregroundStyle(.secondary)
                if let scope = viewModel.scope {
                    ScopeChip(title: scope.title, symbol: scope.symbol, accent: accent)
                }
                QueryField(text: $viewModel.query, focusToken: viewModel.focusToken, fontSize: layout.queryFontSize,
                           placeholder: viewModel.scope.map { "Search \($0.title)…" } ?? QueryField.defaultPlaceholder)
            }
            .padding(.horizontal, 16)
            .frame(height: layout.fieldHeight)
            if !viewModel.chips.isEmpty {
                // What the owning provider understood ("for 45 min"), under the field.
                HStack(spacing: 6) {
                    ForEach(Array(viewModel.chips.enumerated()), id: \.offset) { _, chip in ChipLabel(text: chip) }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: Self.chipsHeight, alignment: .top)
            }

            if !viewModel.results.isEmpty {
                PanelDivider()
                resultsList
                if viewModel.actionsMode == .menu {
                    PanelDivider()
                    actionsMenu
                }
            } else if !Query(viewModel.effectiveQuery).isEmpty {
                PanelDivider()
                Text(viewModel.emptyMessage ?? (viewModel.isIndexing ? "Indexing apps…" : "No apps match “\(viewModel.query)”"))
                    .foregroundStyle(.secondary)
                    .frame(height: 44)
            }
            // Under the list, and in compact mode under the bare field, so the panel keeps its shape.
            if layout.showFooter, !viewModel.results.isEmpty || (layout.compact && Query(viewModel.effectiveQuery).isEmpty) {
                PanelDivider()
                footer
            }
        }
        .frame(width: layout.width)
    }

    private var resultsList: some View {
        let starts = viewModel.sectionStarts
        let useGlass = layout.material.isGlass
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, scored in
                        if starts.contains(index), let section = scored.section {
                            SectionHeader(title: section)
                        }
                        ResultRow(item: scored.item, alias: scored.alias, quickKey: scored.quickKey, isSelected: index == viewModel.selectedIndex, height: layout.rowHeight,
                                  iconSize: layout.iconSize, accent: accent, useGlass: useGlass, showMetadata: layout.subtitles == .always)
                            .id(scored.id)
                            .onTapGesture {
                                viewModel.selectedIndex = index
                                viewModel.runDefaultAction()
                            }
                        if viewModel.actionsMode == .chips, index == viewModel.selectedIndex {
                            ActionChips(actions: scored.item.actions, selected: viewModel.actionIndex ?? 0, accent: accent, useGlass: useGlass,
                                        inset: 10 + layout.iconSize + 10) { viewModel.run($0) }
                        }
                    }
                }
                .padding(8)
            }
            .frame(height: listHeight(headers: starts.filter { $0 < layout.maxVisibleRows }.count))
            .onChange(of: viewModel.selectedIndex) { _, index in
                guard let item = viewModel.results[safe: index] else { return }
                // The first row of a section brings its heading along.
                proxy.scrollTo(item.id, anchor: starts.contains(index) ? .top : nil)
            }
        }
    }

    static let actionRowHeight: CGFloat = 30
    static let footerHeight: CGFloat = 34
    static let chipsHeight: CGFloat = 32

    /// The bar under the list. Left: the feature that owns the query, or nothing. Right: what
    /// Return and the actions key do for the selected row. Hints live here, not on the rows,
    /// so the list stays one line per item and the trailing edge never jumps on selection.
    private var footer: some View {
        let item = viewModel.selected?.item
        return HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                Text(viewModel.context ?? "Mestre")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            if let toast = viewModel.toast {
                HStack(spacing: 8) {
                    PanelDivider(vertical: 14)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.green)
                    Text(toast).font(.system(size: 12, weight: .medium))
                }
            }
            Spacer()
            if let item {
                if let hint = viewModel.bindings.hint(for: .open), let title = item.defaultAction?.title {
                    footerHint(title, hint)
                }
                if viewModel.actionsMode == .chips, let hint = viewModel.bindings.hint(for: .moveRight) {
                    footerHint("Choose", "← " + hint)
                } else if item.actions.count > 1, let hint = viewModel.bindings.hint(for: .actions) {
                    footerHint("Actions", hint)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.footerHeight)
    }

    private func footerHint(_ label: String, _ keys: String) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            KeyHint(keys)
        }
    }

    private var actionsMenu: some View {
        let useGlass = layout.material.isGlass
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Actions").padding(.horizontal, 8)
            ForEach(Array(viewModel.selectedActions.enumerated()), id: \.element.id) { index, action in
                HStack(spacing: 10) {
                    Image(systemName: action.icon ?? "circle")
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                    Text(action.title)
                    Spacer()
                    Text(action.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if let hint = viewModel.bindings.hint(for: action, isDefault: index == 0) {
                        KeyHint(hint)
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(height: Self.actionRowHeight)
                .background(SelectionBackground(isSelected: index == viewModel.actionIndex, accent: accent, useGlass: useGlass, cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { viewModel.run(action) }
            }
        }
        .padding(8)
    }

    /// Enough for `maxVisibleRows` rows plus the headings among them, and half of the next row
    /// when more exist (`panel.peekNextRow`), so the overflow is visible without a scrollbar.
    private func listHeight(headers: Int) -> CGFloat {
        let overflow = viewModel.results.count > layout.maxVisibleRows
        let peek = overflow && layout.peekNextRow ? layout.rowHeight / 2 : 0
        let chips = viewModel.actionsMode == .chips ? Self.chipsHeight : 0
        return CGFloat(min(viewModel.results.count, layout.maxVisibleRows)) * layout.rowHeight + 16 + CGFloat(headers) * Self.headerHeight + peek + chips
    }
}

/// Small uppercase heading above a group of rows.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: SearchView.headerHeight, maxHeight: SearchView.headerHeight, alignment: .bottomLeading)
    }
}

/// A key combo, drawn as a small cap.
struct KeyHint: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 1))
            }
    }
}

/// Selection highlight: Liquid Glass inside a glass panel on macOS 26, a tinted fill otherwise.
struct SelectionBackground: View {
    let isSelected: Bool
    let accent: Color
    let useGlass: Bool
    var cornerRadius: CGFloat = 8

    var body: some View {
        if isSelected {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if #available(macOS 26.0, *), useGlass {
                Color.clear.glassEffect(.regular.tint(accent.opacity(0.28)), in: shape)
            } else {
                shape.fill(accent.opacity(0.16))
            }
        }
    }
}

/// Hairline between the search box, the list, the actions menu and the footer; `vertical`
/// gives a short upright one for the footer's toast.
struct PanelDivider: View {
    var vertical: CGFloat?

    var body: some View {
        let line = Rectangle().fill(.primary.opacity(0.08))
        if let vertical { line.frame(width: 1, height: vertical) } else { line.frame(height: 1) }
    }
}

/// The scope before the field: a feature or quicklink the user entered with ⇥ or ↩.
struct ScopeChip: View {
    let title: String
    let symbol: String?
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
            }
            Text(title).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(SelectionBackground(isSelected: true, accent: accent, useGlass: false, cornerRadius: 6))
        .foregroundStyle(.primary)
        .fixedSize()
    }
}

/// A row's actions unfolded under it (⇥): ← → choose, ↩ runs.
struct ActionChips: View {
    let actions: [ItemAction]
    let selected: Int
    let accent: Color
    let useGlass: Bool
    /// Where the row's title starts, so the chips line up under it.
    let inset: CGFloat
    let run: (ItemAction) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                ChipLabel(text: action.title, selected: index == selected ? (accent, useGlass) : nil)
                    .onTapGesture { run(action) }
            }
            Spacer()
        }
        .padding(.leading, inset)
        .padding(.trailing, 10)
        .frame(height: SearchView.chipsHeight)
    }
}

/// A small rounded label: a parsed chip under the field, or an action chip (selected or not).
struct ChipLabel: View {
    let text: String
    var selected: (accent: Color, useGlass: Bool)?

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background {
                if let selected {
                    SelectionBackground(isSelected: true, accent: selected.accent, useGlass: selected.useGlass, cornerRadius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07))
                }
            }
    }
}
