import Foundation

/// An sRGB colour with 0…1 components.
public struct ParsedColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
        self.alpha = min(1, max(0, alpha))
    }

    var bytes: (Int, Int, Int) { (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) }

    /// "#FF8800" (with "AA" alpha appended when not opaque).
    public var hex: String {
        let (r, g, b) = bytes
        let base = String(format: "#%02X%02X%02X", r, g, b)
        return alpha < 1 ? base + String(format: "%02X", Int((alpha * 255).rounded())) : base
    }

    /// "rgb(255, 136, 0)" or "rgba(255, 136, 0, 0.5)".
    public var rgbString: String {
        let (r, g, b) = bytes
        return alpha < 1 ? "rgba(\(r), \(g), \(b), \(trim(alpha)))" : "rgb(\(r), \(g), \(b))"
    }

    /// "hsl(32, 100%, 50%)".
    public var hslString: String {
        let (h, s, l) = hsl
        let core = "\(Int(h.rounded()) % 360), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%"
        return alpha < 1 ? "hsla(\(core), \(trim(alpha)))" : "hsl(\(core))"
    }

    /// Swift: "Color(red: 1, green: 0.533, blue: 0)".
    public var swiftUIString: String {
        "Color(red: \(trim(red)), green: \(trim(green)), blue: \(trim(blue))" + (alpha < 1 ? ", opacity: \(trim(alpha)))" : ")")
    }

    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let l = (maxC + minC) / 2
        let d = maxC - minC
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        switch maxC {
        case red: h = (green - blue) / d + (green < blue ? 6 : 0)
        case green: h = (blue - red) / d + 2
        default: h = (red - green) / d + 4
        }
        h *= 60
        return (h, s, l)
    }

    public static func fromHSL(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1) -> ParsedColor {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let s = min(1, max(0, saturation)), l = min(1, max(0, lightness))
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return ParsedColor(red: channel(h + 1 / 3), green: channel(h), blue: channel(h - 1 / 3), alpha: alpha)
    }

    private func trim(_ value: Double) -> String { Calculator.format(value, precision: 3) }
}

/// Parses the colour notations people paste: #RGB, #RRGGBB, #RRGGBBAA, rgb()/rgba(),
/// hsl()/hsla() and CSS colour names.
public enum ColorParser {
    /// Cheap gate for the keystroke path.
    public static func mayBeColor(_ lowercased: String, allowNames: Bool = true) -> Bool {
        lowercased.hasPrefix("#") || lowercased.hasPrefix("rgb") || lowercased.hasPrefix("hsl") || (allowNames && names[lowercased] != nil)
    }

    /// `allowNames` false skips CSS names, so "tan" can stay an app search.
    public static func parse(_ text: String, allowNames: Bool = true) -> ParsedColor? {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        if allowNames, let named = names[s] { return parseHex(named) }
        if s.hasPrefix("#") { return parseHex(s) }
        if s.hasPrefix("rgb(") || s.hasPrefix("rgba(") { return parseFunction(s, parseRGB) }
        if s.hasPrefix("hsl(") || s.hasPrefix("hsla(") { return parseFunction(s, parseHSL) }
        return nil
    }

    private static func parseRGB(_ parts: [String]) -> ParsedColor? {
        guard parts.count >= 3, let r = component(parts[0]), let g = component(parts[1]), let b = component(parts[2]), let a = alphaPart(parts) else { return nil }
        return ParsedColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func parseHSL(_ parts: [String]) -> ParsedColor? {
        guard parts.count >= 3, let h = hue(parts[0]), let sat = percent(parts[1]), let light = percent(parts[2]), let a = alphaPart(parts) else { return nil }
        return ParsedColor.fromHSL(hue: h, saturation: sat, lightness: light, alpha: a)
    }

    /// Degrees by default; "turn", "rad" and "grad" as in CSS.
    private static func hue(_ text: String) -> Double? {
        if text.hasSuffix("turn"), let v = Double(text.dropLast(4)) { return v * 360 }
        if text.hasSuffix("grad"), let v = Double(text.dropLast(4)) { return v * 0.9 }
        if text.hasSuffix("rad"), let v = Double(text.dropLast(3)) { return v * 180 / .pi }
        if text.hasSuffix("deg") { return Double(text.dropLast(3)) }
        return Double(text)
    }

    /// Opaque with three parts; the fourth must parse; a fifth is an error.
    private static func alphaPart(_ parts: [String]) -> Double? {
        switch parts.count {
        case 3: return 1
        case 4: return alpha(parts[3])
        default: return nil
        }
    }

    private static func parseHex(_ s: String) -> ParsedColor? {
        var hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        if hex.count <= 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }
        let hasAlpha = hex.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return ParsedColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func parseFunction(_ s: String, _ build: ([String]) -> ParsedColor?) -> ParsedColor? {
        guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")"), open < close, s.index(after: close) == s.endIndex else { return nil }
        let inner = s[s.index(after: open)..<close]
        let parts = inner.split { $0 == "," || $0 == " " || $0 == "/" }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return build(parts)
    }

    /// "255" or "100%" → 0…1.
    private static func component(_ text: String) -> Double? {
        if text.hasSuffix("%") { return percent(text) }
        return Double(text).map { $0 / 255 }
    }

    private static func percent(_ text: String) -> Double? {
        guard text.hasSuffix("%"), let value = Double(text.dropLast()) else { return nil }
        return value / 100
    }

    private static func alpha(_ text: String) -> Double? {
        text.hasSuffix("%") ? percent(text) : Double(text)
    }

    /// The CSS named colours.
    static let names: [String: String] = [
        "black": "#000000", "white": "#ffffff", "red": "#ff0000", "lime": "#00ff00", "blue": "#0000ff", "yellow": "#ffff00",
        "cyan": "#00ffff", "aqua": "#00ffff", "magenta": "#ff00ff", "fuchsia": "#ff00ff", "silver": "#c0c0c0", "gray": "#808080",
        "grey": "#808080", "maroon": "#800000", "olive": "#808000", "green": "#008000", "purple": "#800080", "teal": "#008080",
        "navy": "#000080", "orange": "#ffa500", "pink": "#ffc0cb", "brown": "#a52a2a", "coral": "#ff7f50", "crimson": "#dc143c",
        "gold": "#ffd700", "indigo": "#4b0082", "ivory": "#fffff0", "khaki": "#f0e68c", "lavender": "#e6e6fa", "salmon": "#fa8072",
        "tomato": "#ff6347", "turquoise": "#40e0d0", "violet": "#ee82ee", "beige": "#f5f5dc", "chocolate": "#d2691e", "tan": "#d2b48c",
        "orchid": "#da70d6", "plum": "#dda0dd", "skyblue": "#87ceeb", "steelblue": "#4682b4", "slategray": "#708090", "slategrey": "#708090",
        "darkgray": "#a9a9a9", "darkgrey": "#a9a9a9", "lightgray": "#d3d3d3", "lightgrey": "#d3d3d3", "dimgray": "#696969", "dimgrey": "#696969",
        "royalblue": "#4169e1", "dodgerblue": "#1e90ff", "deepskyblue": "#00bfff", "forestgreen": "#228b22", "seagreen": "#2e8b57",
        "limegreen": "#32cd32", "darkgreen": "#006400", "darkred": "#8b0000", "darkblue": "#00008b", "firebrick": "#b22222",
        "hotpink": "#ff69b4", "deeppink": "#ff1493", "orangered": "#ff4500", "goldenrod": "#daa520", "wheat": "#f5deb3", "mintcream": "#f5fffa",
        "rebeccapurple": "#663399", "aquamarine": "#7fffd4", "chartreuse": "#7fff00", "sienna": "#a0522d", "peru": "#cd853f", "linen": "#faf0e6",
    ]
}
