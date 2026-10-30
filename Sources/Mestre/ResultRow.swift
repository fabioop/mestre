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
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(minWidth: Self.minSubtitleWidth, alignment: .leading)
                    }
                }
                titleLine
            }
            Spacer(minLength: 12)
            if let quickKey {
                KeyHint(quickKey)
            }
            Text(item.kind.label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(SelectionBackground(isSelected: isSelected, accent: accent, useGlass: useGlass, cornerRadius: 8))
        .contentShape(Rectangle())
    }

    static let minSubtitleWidth: CGFloat = 96

    /// The title with its alias and running dot; truncates on its own when the subtitle is gone.
    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            if let alias {
                Text("(\(alias))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if item.isActive {
                Circle()
                    .fill(Color.green)
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
            RoundedRectangle(cornerRadius: iconSize * 0.25, style: .continuous)
                .fill(isSelected ? accent.opacity(0.18) : Color.primary.opacity(0.07))
                .overlay {
                    Image(systemName: item.iconSymbol ?? "circle.dashed")
                        .font(.system(size: iconSize * 0.5, weight: .medium))
                        .foregroundStyle(isSelected ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                }
        }
    }
}
