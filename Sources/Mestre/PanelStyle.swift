import AppKit
import MestreCore
import SwiftUI

/// A theme resolved into what the views draw with: parsed once per theme change, never per
/// render, because the rows read it on every keystroke. The defaults are the panel's own look,
/// system colours over the material, so the default theme draws exactly what it always did.
struct PanelStyle {
    var panel: Color?
    var border: Color?
    var borderWidth: CGFloat = 0
    var ink = AnyShapeStyle(.primary)
    var inkSecondary = AnyShapeStyle(.secondary)
    var inkTertiary = AnyShapeStyle(.tertiary)
    var divider = AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.08))
    var running = Color.green
    var selection: Color?
    var selectionInk = AnyShapeStyle(.primary)
    var selectionSecondary = AnyShapeStyle(.secondary)
    var iconTile: Color?
    var iconSymbol: Color?
    var selectedIconTile: Color?
    var selectedIconSymbol: Color?
    var keyCap = AnyShapeStyle(HierarchicalShapeStyle.quaternary.opacity(0.5))
    var keyCapInk = AnyShapeStyle(.secondary)
    var keyCapEdge = AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.08))
    var selectedKeyInk: AnyShapeStyle?
    var primaryKey: Color?
    var primaryKeyInk: Color?
    var field: Color?
    var fieldSecondary = AnyShapeStyle(.secondary)
    var fieldTextColor: NSColor?
    var fieldPlaceholderColor: NSColor?
    var caretColor: NSColor?
    var footer: Color?
    var footerInk = AnyShapeStyle(.primary)
    var footerSecondary = AnyShapeStyle(.secondary)
    var kinds: [String: Color] = [:]
    var tiles: [(fill: Color, ink: Color)] = []
    var rowRadius: CGFloat = 8
    /// Nil keeps a quarter of the icon size.
    var iconRadius: CGFloat?
    var tileRadius: CGFloat = 16
    var sectionCase: Text.Case? = .uppercase
    var kindCase: Text.Case?
    private var uiFace = Face.system
    /// Key caps stay rounded so ⌘ ⌥ ↩ sit evenly, unless the theme names a typeface.
    private var capFace = Face.rounded
    private var queryFace = Face.system
    private var queryWeight = NSFont.Weight.regular

    /// A system design or an installed family, checked once when the theme is resolved.
    private enum Face {
        case system, rounded, monospaced, serif, family(String)

        init(_ name: String?) {
            switch name?.trimmingCharacters(in: .whitespaces) {
            case nil, "", "system": self = .system
            case "rounded": self = .rounded
            case "monospaced": self = .monospaced
            case "serif": self = .serif
            case let family?: self = NSFontManager.shared.availableFontFamilies.contains(family) ? .family(family) : .system
            }
        }

        func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
            switch self {
            case .system: return .system(size: size, weight: weight)
            case .rounded: return .system(size: size, weight: weight, design: .rounded)
            case .monospaced: return .system(size: size, weight: weight, design: .monospaced)
            case .serif: return .system(size: size, weight: weight, design: .serif)
            case .family(let name): return .custom(name, size: size).weight(weight)
            }
        }

        func nsFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
            let system = NSFont.systemFont(ofSize: size, weight: weight)
            func designed(_ design: NSFontDescriptor.SystemDesign) -> NSFont {
                system.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? system
            }
            switch self {
            case .system: return system
            case .rounded: return designed(.rounded)
            case .monospaced: return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            case .serif: return designed(.serif)
            case .family(let name):
                // By family and weight: NSFont(name:) alone always gives the family's regular.
                let traits: [NSFontDescriptor.TraitKey: Any] = [.weight: weight.rawValue]
                let descriptor = NSFontDescriptor(fontAttributes: [.family: name, .traits: traits])
                return NSFont(descriptor: descriptor, size: size) ?? NSFont(name: name, size: size) ?? system
            }
        }
    }

    init() {}

    init(theme: Theme, dark: Bool) {
        let colors = theme.palette(dark: dark)
        func color(_ text: String?) -> ParsedColor? { text.flatMap { ColorParser.parse($0) } }
        func swiftUI(_ text: String?) -> Color? { color(text).map(Self.color) }
        func style(_ text: String?) -> AnyShapeStyle? { swiftUI(text).map { AnyShapeStyle($0) } }
        func appKit(_ text: String?) -> NSColor? {
            color(text).map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) }
        }

        panel = swiftUI(colors.panel)
        border = swiftUI(colors.border)
        borderWidth = border == nil ? 0 : CGFloat(theme.borderWidth ?? 1)
        ink = style(colors.ink) ?? ink
        inkSecondary = style(colors.inkSecondary) ?? inkSecondary
        inkTertiary = style(colors.inkSecondary) ?? inkTertiary
        divider = style(colors.divider) ?? divider
        running = swiftUI(colors.running) ?? running
        selection = swiftUI(colors.selection)
        selectionInk = style(colors.selectionInk) ?? ink
        selectionSecondary = style(colors.selectionSecondary) ?? inkSecondary
        iconTile = swiftUI(colors.iconTile)
        iconSymbol = swiftUI(colors.iconSymbol)
        selectedIconTile = swiftUI(colors.selectedIconTile)
        selectedIconSymbol = swiftUI(colors.selectedIconSymbol)
        let paintedCap = swiftUI(colors.keyCap)
        keyCap = paintedCap.map { AnyShapeStyle($0) } ?? keyCap
        keyCapInk = style(colors.keyCapInk) ?? inkSecondary
        keyCapEdge = style(colors.keyCapEdge) ?? (paintedCap == nil ? keyCapEdge : AnyShapeStyle(Color.clear))
        // A theme that paints the selection but not the caps: the default cap ink may not read on it.
        selectedKeyInk = style(colors.selectedKeyInk) ?? (selection != nil && paintedCap == nil ? selectionSecondary : nil)
        primaryKey = swiftUI(colors.primaryKey)
        primaryKeyInk = swiftUI(colors.primaryKeyInk)
        field = swiftUI(colors.field)
        fieldSecondary = style(colors.fieldSecondary) ?? inkSecondary
        fieldTextColor = appKit(colors.fieldInk) ?? appKit(colors.ink)
        fieldPlaceholderColor = appKit(colors.fieldSecondary) ?? appKit(colors.inkSecondary)
        caretColor = appKit(colors.caret) ?? fieldTextColor
        footer = swiftUI(colors.footer)
        footerInk = style(colors.footerInk) ?? ink
        footerSecondary = style(colors.footerSecondary) ?? inkSecondary
        kinds = (colors.kinds ?? [:]).compactMapValues { swiftUI($0) }
        tiles = (colors.tiles ?? []).compactMap { color($0) }.map { (Self.color($0), Self.color($0.readableInk)) }
        rowRadius = CGFloat(theme.rowRadius ?? 8)
        iconRadius = theme.iconRadius.map { CGFloat($0) }
        tileRadius = CGFloat(theme.tileRadius ?? 16)
        switch theme.labelCase {
        case .upper: (sectionCase, kindCase) = (.uppercase, .uppercase)
        case .lower: (sectionCase, kindCase) = (.lowercase, .lowercase)
        case .none?: (sectionCase, kindCase) = (nil, nil)
        case nil: break
        }
        uiFace = Face(theme.fonts.ui)
        capFace = theme.fonts.ui == nil ? .rounded : uiFace
        queryFace = Face(theme.fonts.query ?? theme.fonts.ui)
        queryWeight = Self.weight(theme.fonts.queryWeight)
    }

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { uiFace.font(size, weight) }
    func capFont(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { capFace.font(size, weight) }
    func queryFont(size: CGFloat) -> NSFont { queryFace.nsFont(size, queryWeight) }

    /// Selection behind an action or a chip: a step inside a row's corner, as nesting asks.
    var actionRadius: CGFloat { max(0, rowRadius - 2) }
    /// A cap follows the corners around it: square in a square theme, a pill in a round one.
    var capRadius: CGFloat { rowRadius < 5 ? rowRadius : rowRadius >= 14 ? 10 : 5 }
    /// The fill behind unselected symbols and chips.
    var quietFill: Color { iconTile ?? Color.primary.opacity(0.07) }

    /// The palette's next tile, or the quiet fill when the theme has no palette.
    func tile(_ index: Int) -> (fill: Color, ink: Color?) {
        guard !tiles.isEmpty else { return (quietFill, nil) }
        let tile = tiles[index % tiles.count]
        return (tile.fill, tile.ink)
    }

    private static func color(_ c: ParsedColor) -> Color {
        Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    private static func weight(_ name: String?) -> NSFont.Weight {
        switch name?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "light": return .light
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        default: return .regular
        }
    }
}

private struct PanelStyleKey: EnvironmentKey {
    static let defaultValue = PanelStyle()
}

extension EnvironmentValues {
    var panelStyle: PanelStyle {
        get { self[PanelStyleKey.self] }
        set { self[PanelStyleKey.self] = newValue }
    }
}
