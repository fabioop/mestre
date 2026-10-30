import AppKit
import MestreCore

struct ColorItem: SearchItem {
    let format: String
    let value: String
    let icon: NSImage?

    var id: String { format }
    var title: String { value }
    var subtitle: String? { format }
    var kind: ItemKind { .color }
    var actions: [ItemAction] { Self.actions }

    static let actions = [ItemAction(id: "copy", title: "Copy", icon: "doc.on.doc")]
}

/// Typing a colour ("#ff8800", "rgb(255, 136, 0)", "hsl(32, 100%, 50%)", "coral") shows it
/// in every notation with a swatch; Return copies the highlighted one.
@MainActor
final class ColorProvider: ResultProvider {
    nonisolated let id = "colors"
    nonisolated let declaredActions = ColorItem.actions
    var settings = Config.Colors()
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    private static let swatches = NSCache<NSString, NSImage>()

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "colors", title: "Colour Converter", subtitle: "#ff8800, rgb(), hsl() → every notation with a swatch", symbol: "paintpalette", completion: "#")
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.enabled, ColorParser.mayBeColor(query.lowercased, allowNames: settings.names),
              let color = ColorParser.parse(query.text, allowNames: settings.names) else { return [] }
        let swatch = Self.swatch(for: color)
        let items = settings.formats.compactMap { format -> ColorItem? in
            switch format {
            case "hex": return ColorItem(format: "Hex", value: color.hex, icon: swatch)
            case "rgb": return ColorItem(format: "RGB", value: color.rgbString, icon: swatch)
            case "hsl": return ColorItem(format: "HSL", value: color.hslString, icon: swatch)
            case "swiftui": return ColorItem(format: "SwiftUI", value: color.swiftUIString, icon: swatch)
            default: return nil
            }
        }
        return ScoredItem.pinned(items, provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let item = item as? ColorItem else { return }
        item.value.copyToPasteboard()
        dismiss?()
    }

    /// A rounded 32pt square of the colour, cached by hex.
    static func swatch(for color: ParsedColor) -> NSImage {
        let key = color.hex as NSString
        if let cached = swatches.object(forKey: key) { return cached }
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7).fill()
            NSColor.separatorColor.setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2.5, dy: 2.5), xRadius: 7, yRadius: 7).stroke()
            return true
        }
        swatches.setObject(image, forKey: key)
        return image
    }
}
