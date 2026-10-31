import MestreCore
import SwiftUI

struct ResultRow: View {
    let item: any SearchItem
    /// The alias that matched, shown as "(ff)" after the title.
    var alias: String?
    /// The row's quick key, shown as a cap before the kind.
    var quickKey: String?
    let isSelected: Bool
    let height: Double
    var iconSize: Double = 28
    let accent: Color
    let useGlass: Bool
    /// Draw a metadata second line even though the row isn't selected (`panel.subtitles: always`).
    var showMetadata = true
    @Environment(\.panelStyle) private var style

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: iconSize, height: iconSize)
            // Title and subtitle on one line. The subtitle truncates first, and drops out below
            // `minSubtitleWidth` rather than leaving a stray character; a long title then truncates.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleLine.fixedSize()
                    if let subtitle = secondLine {
                        Text(subtitle)
                            .font(style.font(13))
                            .foregroundStyle(isSelected ? style.selectionSecondary : style.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(minWidth: Self.minSubtitleWidth, alignment: .leading)
                    }
                }
                titleLine
            }
            Spacer(minLength: 12)
            if let quickKey {
                KeyHint(quickKey, onSelection: isSelected)
            }
            Text(item.kind.label)
                .font(style.font(12))
                .textCase(style.kindCase)
                .foregroundStyle(isSelected ? style.selectionSecondary : style.inkSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(SelectionBackground(isSelected: isSelected, accent: accent, useGlass: useGlass, cornerRadius: style.rowRadius))
        .contentShape(Rectangle())
    }

    static let minSubtitleWidth: CGFloat = 96

    /// The title with its alias and running dot; truncates on its own when the subtitle is gone.
    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.title)
                .font(style.font(14, .medium))
                .foregroundStyle(isSelected ? style.selectionInk : style.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            if let alias {
                Text("(\(alias))")
                    .font(style.font(13))
                    .foregroundStyle(isSelected ? style.selectionSecondary : style.inkSecondary)
                    .fixedSize()
            }
            if item.isActive {
                Circle()
                    .fill(style.running)
                    .frame(width: 6, height: 6)
                    .help("Running")
            }
        }
    }

    /// The subtitle, or nil: metadata stays off unselected rows when `showMetadata` is false,
    /// so the list reads as one line per item.
    private var secondLine: String? {
        item.subtitleRole == .content || showMetadata || isSelected ? item.subtitle?.nilIfEmpty : nil
    }

    /// App icons as they are; symbols on a soft rounded tile so every row has the same weight.
    @ViewBuilder private var iconView: some View {
        if let icon = item.icon {
            Image(nsImage: icon).resizable()
        } else {
            let hue = style.kinds[item.kind.rawValue]
            RoundedRectangle(cornerRadius: style.iconRadius ?? iconSize * 0.25, style: .continuous)
                .fill(isSelected ? style.selectedIconTile ?? accent.opacity(0.18) : hue?.opacity(0.18) ?? style.quietFill)
                .overlay {
                    Image(systemName: item.iconSymbol ?? "circle.dashed")
                        .font(style.font(iconSize * 0.5, .medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(style.selectedIconSymbol ?? accent) : (hue ?? style.iconSymbol).map { AnyShapeStyle($0) } ?? style.inkSecondary)
                }
        }
    }
}
