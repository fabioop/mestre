import MestreCore
import SwiftUI

/// What the tiles show besides their rows, read when the empty query is searched (so when
/// the panel opens). Nothing here ticks: the clock is as of that moment.
struct HomeTileInfo {
    var now = Date()
    var power: PowerSource?
    var keepAwakeValue = "Off"
    var keepAwakeDetail: String?
    var clipboardTitle: String?
    var clipboardAge: String?
}

/// The home screen as tiles (`home.layout: tiles`), off by default. Its rows are the view
/// model's ordinary results, so selection, Return, ⌘K and the footer work as in the list.
struct HomeTilesView: View {
    @ObservedObject var viewModel: SearchViewModel
    @Environment(\.panelStyle) private var style

    private static let gap: CGFloat = 8
    /// The selection ring sits outside the tile with a sliver of panel showing, so it reads on
    /// any tile fill. It uses the panel's ink, which a theme keeps readable on the panel.
    private static let ringOffset: CGFloat = 4

    var body: some View {
        let rowHeight = CGFloat(viewModel.home.tileHeight)
        let column = (CGFloat(viewModel.layout.width) - 16 - 3 * Self.gap) / 4
        let recents = Array(viewModel.results.prefix(viewModel.tileRecentCount).enumerated())
        let items = Array(viewModel.results.dropFirst(viewModel.tileRecentCount).enumerated())
        VStack(spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                clock.frame(width: column)
                statusStack.frame(width: column)
                recentTile(recents, cell: (2 * column + Self.gap - 20 - 3 * 4) / 4).frame(maxWidth: .infinity)
            }
            .frame(height: rowHeight)
            if !items.isEmpty {
                HStack(spacing: Self.gap) {
                    ForEach(items, id: \.element.id) { index, scored in
                        itemTile(scored, index: viewModel.tileRecentCount + index, palette: 3 + index)
                            .frame(width: index == 0 ? 2 * column + Self.gap : column)
                    }
                }
                .frame(height: rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Tiles

    private func shape(_ radius: CGFloat? = nil) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius ?? style.tileRadius, style: .continuous)
    }

    private func ink(of tile: (fill: Color, ink: Color?)) -> AnyShapeStyle {
        tile.ink.map { AnyShapeStyle($0) } ?? style.ink
    }

    private var clock: some View {
        let tile = style.tile(0)
        let hands = tile.ink ?? Color.primary
        let accent = viewModel.accent
        let now = viewModel.tileInfo.now
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            func point(_ turns: Double, _ length: CGFloat) -> CGPoint {
                let angle = turns * 2 * .pi - .pi / 2
                return CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
            }
            func line(_ from: CGPoint, _ to: CGPoint, _ color: Color, _ width: CGFloat) {
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            for hour in 0..<12 {
                line(point(Double(hour) / 12, radius * 0.86), point(Double(hour) / 12, radius * 0.96), hands.opacity(0.55), 1.5)
            }
            let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
            let minute = Double(parts.minute ?? 0), hour = Double((parts.hour ?? 0) % 12)
            line(center, point((hour + minute / 60) / 12, radius * 0.5), hands, 4)
            line(center, point(minute / 60, radius * 0.76), hands, 3)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(accent))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape().fill(tile.fill))
        .accessibilityLabel(now.formatted(date: .omitted, time: .shortened))
    }

    private var statusStack: some View {
        let info = viewModel.tileInfo
        let percent = info.power?.batteryPercent
        return VStack(spacing: Self.gap) {
            statusTile(index: 1, label: percent == nil ? "Power" : "Battery", value: percent.map { "\($0)%" } ?? "AC")
            statusTile(index: 2, label: info.now.formatted(.dateTime.weekday(.abbreviated).day()), value: info.now.formatted(date: .omitted, time: .shortened))
        }
    }

    private func statusTile(index: Int, label: String, value: String) -> some View {
        let tile = style.tile(index)
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).font(style.font(12, .semibold))
            Spacer(minLength: 0)
            Text(value)
                .font(style.font(26, .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(ink(of: tile))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(shape().fill(tile.fill))
    }

    private func recentTile(_ recents: [(offset: Int, element: ScoredItem)], cell: CGFloat) -> some View {
        let tile = style.tile(0)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Recent").font(style.font(12, .semibold)).foregroundStyle(ink(of: tile)).padding(.leading, 4)
            HStack(spacing: 4) {
                // Only while it can come true: recents can be switched off.
                if recents.isEmpty, viewModel.home.recentCount > 0, viewModel.ranking.showRecents {
                    Text("Apps you open appear here")
                        .font(style.font(12))
                        .foregroundStyle(ink(of: tile))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(recents, id: \.element.id) { index, scored in
                    let selected = index == viewModel.selectedIndex
                    VStack(spacing: 6) {
                        icon(for: scored.item, size: min(44, cell - 8))
                        Text(scored.item.title)
                            .font(style.font(12, .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(ink(of: tile))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .frame(width: cell)
                    .overlay {
                        // The same ring as the item tiles, inside this tile so it stays clear of
                        // its neighbours, in the tile's own ink so it reads on any fill.
                        if selected {
                            shape(style.tileRadius < 6 ? style.tileRadius : max(0, style.tileRadius - 6))
                                .strokeBorder(ink(of: tile), lineWidth: 2)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { open(index) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape().fill(tile.fill))
    }

    private func itemTile(_ scored: ScoredItem, index: Int, palette: Int) -> some View {
        let tile = style.tile(palette)
        let info = viewModel.tileInfo
        let (value, detail): (String?, String?) = switch scored.item.id {
        case "keepAwake": (info.keepAwakeValue, info.keepAwakeDetail)
        case "clipboard": (info.clipboardTitle, info.clipboardAge)
        default: (nil, nil)
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: scored.item.iconSymbol ?? "circle.dashed").font(style.font(14, .semibold))
                if value != nil {
                    Text(scored.item.title).font(style.font(12, .semibold)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(value ?? scored.item.title)
                .font(style.font(index == viewModel.tileRecentCount ? 36 : 20, .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(style.font(12, .medium)).lineLimit(1)
            }
        }
        .foregroundStyle(ink(of: tile))
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(shape().fill(tile.fill))
        .overlay {
            if index == viewModel.selectedIndex {
                // A nearly square theme keeps its corners square.
                shape(style.tileRadius < 6 ? style.tileRadius : style.tileRadius + Self.ringOffset)
                    .strokeBorder(style.ink, lineWidth: 2)
                    .padding(-Self.ringOffset)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open(index) }
    }

    @ViewBuilder private func icon(for item: any SearchItem, size: CGFloat) -> some View {
        if let image = item.icon {
            Image(nsImage: image).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: item.iconSymbol ?? "circle.dashed").font(style.font(size / 2, .medium)).frame(width: size, height: size)
        }
    }

    private func open(_ index: Int) {
        viewModel.selectedIndex = index
        viewModel.runDefaultAction()
    }
}
