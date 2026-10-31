import MestreCore
import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: SearchViewModel

    static let headerHeight: CGFloat = 30
    private var layout: Config.Panel { viewModel.layout }
    private var accent: Color { viewModel.accent }
    private var style: PanelStyle { viewModel.style }
    /// A filled field or footer sits this far inside the panel.
    private static let barInset: CGFloat = 8
    /// Their corners run parallel to the panel's, whatever radius it has.
    private var barRadius: CGFloat { max(0, layout.cornerRadius - Self.barInset) }
    static let filledFooterHeight: CGFloat = 42
    /// Something sits under the field: the list, or the tiles even with no rows of their own.
    private var hasRows: Bool { !viewModel.results.isEmpty || viewModel.isTilesHome }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(style.font(layout.queryFontSize * 0.8, .medium))  // icon tracks the query font
                    .foregroundStyle(style.fieldSecondary)
                if let scope = viewModel.scope {
                    ScopeChip(title: scope.title, symbol: scope.symbol, accent: accent)
                }
                QueryField(text: $viewModel.query, focusToken: viewModel.focusToken, font: style.queryFont(size: layout.queryFontSize),
                           placeholder: viewModel.scope.map { "Search \($0.title)…" } ?? QueryField.defaultPlaceholder,
                           textColor: style.fieldTextColor, placeholderColor: style.fieldPlaceholderColor, caretColor: style.caretColor)
            }
            .padding(.horizontal, 16)
            .frame(height: layout.fieldHeight)
            .background {
                if let field = style.field {
                    RoundedRectangle(cornerRadius: barRadius, style: .continuous).fill(field)
                }
            }
            .padding([.horizontal, .top], style.field == nil ? 0 : Self.barInset)
            // The list and the tiles bring their own space under a filled field; nothing else does.
            .padding(.bottom, style.field != nil && !hasRows ? Self.barInset : 0)
            if !viewModel.chips.isEmpty {
                // What the owning provider understood ("for 45 min"), under the field.
                HStack(spacing: 6) {
                    ForEach(Array(viewModel.chips.enumerated()), id: \.offset) { _, chip in ChipLabel(text: chip) }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: Self.chipsHeight, alignment: .top)
            }

            // The tiles show the clock and power even with no rows to go with them.
            if hasRows {
                if style.field == nil { PanelDivider() }
                if viewModel.isTilesHome {
                    HomeTilesView(viewModel: viewModel).padding(8)
                } else {
                    resultsList
                }
                if viewModel.actionsMode == .menu {
                    PanelDivider()
                    actionsMenu
                }
            } else if !Query(viewModel.effectiveQuery).isEmpty {
                if style.field == nil { PanelDivider() }
                Text(viewModel.emptyMessage ?? (viewModel.isIndexing ? "Indexing apps…" : "No apps match “\(viewModel.query)”"))
                    .font(style.font(13))
                    .foregroundStyle(style.inkSecondary)
                    .frame(height: 44)
            }
            // Under the list, and in compact mode under the bare field, so the panel keeps its shape.
            if layout.showFooter, hasRows || (layout.compact && Query(viewModel.effectiveQuery).isEmpty) {
                if style.footer == nil { PanelDivider() }
                footer
            }
        }
        .frame(width: layout.width)
        .foregroundStyle(style.ink)
        .background {
            if let panel = style.panel {
                RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous).fill(panel)
            }
        }
        .overlay {
            if let border = style.border {
                RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous).strokeBorder(border, lineWidth: style.borderWidth)
            }
        }
        .environment(\.panelStyle, style)
    }

    private var resultsList: some View {
        let starts = viewModel.sectionStarts
        let useGlass = layout.material.isGlass
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, scored in
                        if starts.contains(index), let section = scored.section {
                            SectionHeader(title: section, color: style.kinds[scored.item.kind.rawValue])
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
                    .font(style.font(11, .medium))
                Text(viewModel.context ?? "Mestre")
                    .font(style.font(12, .medium))
            }
            .foregroundStyle(style.footerSecondary)
            if let toast = viewModel.toast {
                HStack(spacing: 8) {
                    PanelDivider(vertical: 14)
                    Image(systemName: "checkmark").font(style.font(10, .semibold)).foregroundStyle(style.running)
                    Text(toast).font(style.font(12, .medium)).foregroundStyle(style.footerInk)
                }
            }
            Spacer()
            if let item {
                if let hint = viewModel.bindings.hint(for: .open), let title = item.defaultAction?.title {
                    footerHint(title, hint, primary: true)
                }
                if viewModel.actionsMode == .chips, let hint = viewModel.bindings.hint(for: .moveRight) {
                    footerHint("Choose", "← " + hint)
                } else if item.actions.count > 1, let hint = viewModel.bindings.hint(for: .actions) {
                    footerHint("Actions", hint)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, style.footer == nil ? 16 : 10)
        .frame(height: style.footer == nil ? Self.footerHeight : Self.filledFooterHeight)
        .background {
            if let fill = style.footer {
                RoundedRectangle(cornerRadius: barRadius, style: .continuous).fill(fill)
            }
        }
        .padding([.horizontal, .bottom], style.footer == nil ? 0 : Self.barInset)
    }

    private func footerHint(_ label: String, _ keys: String, primary: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text(label).font(style.font(12)).foregroundStyle(style.footerSecondary)
            KeyHint(keys, primary: primary)
        }
    }

    private var actionsMenu: some View {
        let useGlass = layout.material.isGlass
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Actions").padding(.horizontal, 8)
            ForEach(Array(viewModel.selectedActions.enumerated()), id: \.element.id) { index, action in
                let isSelected = index == viewModel.actionIndex
                HStack(spacing: 10) {
                    Image(systemName: action.icon ?? "circle")
                        .frame(width: 16)
                        .foregroundStyle(isSelected ? style.selectionSecondary : style.inkSecondary)
                    Text(action.title)
                        .foregroundStyle(isSelected ? style.selectionInk : style.ink)
                    Spacer()
                    Text(action.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(isSelected ? style.selectionSecondary : style.inkTertiary)
                    if let hint = viewModel.bindings.hint(for: action, isDefault: index == 0) {
                        KeyHint(hint, onSelection: isSelected)
                    }
                }
                .font(style.font(13))
                .padding(.horizontal, 10)
                .frame(height: Self.actionRowHeight)
                .background(SelectionBackground(isSelected: isSelected, accent: accent, useGlass: useGlass, cornerRadius: style.actionRadius))
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
    /// The kind's colour, when the theme gives kinds one.
    var color: Color?
    @Environment(\.panelStyle) private var style

    var body: some View {
        Text(title)
            .textCase(style.sectionCase)
            .font(style.font(11, .semibold))
            .kerning(0.5)
            .foregroundStyle(color.map { AnyShapeStyle($0) } ?? style.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, minHeight: SearchView.headerHeight, maxHeight: SearchView.headerHeight, alignment: .bottomLeading)
    }
}

/// A key combo, drawn as a small cap.
struct KeyHint: View {
    let keys: String
    /// The footer's Return hint, the one cap a theme may colour on its own.
    let primary: Bool
    /// On the selected row, where a theme may need another ink for the cap to read.
    let onSelection: Bool
    @Environment(\.panelStyle) private var style

    init(_ keys: String, primary: Bool = false, onSelection: Bool = false) {
        self.keys = keys
        self.primary = primary
        self.onSelection = onSelection
    }

    var body: some View {
        let fill = primary ? style.primaryKey.map { AnyShapeStyle($0) } ?? style.keyCap : style.keyCap
        let selectedInk = onSelection ? style.selectedKeyInk : nil
        let ink = primary ? style.primaryKeyInk.map { AnyShapeStyle($0) } ?? style.keyCapInk : selectedInk ?? style.keyCapInk
        let edge = primary && style.primaryKey != nil ? AnyShapeStyle(Color.clear) : selectedInk ?? style.keyCapEdge
        let shape = RoundedRectangle(cornerRadius: style.capRadius, style: .continuous)
        Text(keys)
            .font(style.capFont(11))
            .foregroundStyle(ink)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background {
                shape.fill(fill).overlay(shape.strokeBorder(edge, lineWidth: 1))
            }
    }
}

/// Selection highlight: Liquid Glass inside a glass panel on macOS 26, a tinted fill otherwise.
struct SelectionBackground: View {
    let isSelected: Bool
    let accent: Color
    let useGlass: Bool
    var cornerRadius: CGFloat = 8
    @Environment(\.panelStyle) private var style

    var body: some View {
        if isSelected {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if let fill = style.selection {
                shape.fill(fill)
            } else if #available(macOS 26.0, *), useGlass {
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
    @Environment(\.panelStyle) private var style

    var body: some View {
        let line = Rectangle().fill(style.divider)
        if let vertical { line.frame(width: 1, height: vertical) } else { line.frame(height: 1) }
    }
}

/// The scope before the field: a feature or quicklink the user entered with ⇥ or ↩.
struct ScopeChip: View {
    let title: String
    let symbol: String?
    let accent: Color
    @Environment(\.panelStyle) private var style

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(style.font(11, .medium))
            }
            Text(title).font(style.font(13, .medium))
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(SelectionBackground(isSelected: true, accent: accent, useGlass: false, cornerRadius: style.actionRadius))
        .foregroundStyle(style.selectionInk)
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
    @Environment(\.panelStyle) private var style

    var body: some View {
        Text(text)
            .font(style.font(12, .medium))
            .foregroundStyle(selected == nil ? style.ink : style.selectionInk)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background {
                if let selected {
                    SelectionBackground(isSelected: true, accent: selected.accent, useGlass: selected.useGlass, cornerRadius: style.actionRadius)
                } else {
                    RoundedRectangle(cornerRadius: style.actionRadius, style: .continuous).fill(style.quietFill)
                }
            }
    }
}
