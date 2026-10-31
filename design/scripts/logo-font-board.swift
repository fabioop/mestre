// Draws a board of app icon candidates: the current ground and ink, with the M set in free fonts.
// Usage: swift design/scripts/logo-font-board.swift <fonts dir> <out.png> <round>
import AppKit
import CoreText

let fontsDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])
let round = Int(CommandLine.arguments[3])!

let putty = NSColor(srgbRed: 0.863, green: 0.855, blue: 0.824, alpha: 1)
let ink = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.106, alpha: 1)

enum Source {
    case current
    case file(String, wght: Double?, wdth: Double? = nil)
}

struct Option {
    let name: String
    let detail: String
    let source: Source
}

let rounds: [Int: [Option]] = [1: [
    Option(name: "Current", detail: "hand-drawn strokes", source: .current),
    Option(name: "JetBrains Mono", detail: "Regular", source: .file("JetBrainsMono", wght: 400)),
    Option(name: "JetBrains Mono", detail: "Medium", source: .file("JetBrainsMono", wght: 500)),
    Option(name: "JetBrains Mono", detail: "Bold", source: .file("JetBrainsMono", wght: 700)),
    Option(name: "JetBrains Mono", detail: "ExtraBold", source: .file("JetBrainsMono", wght: 800)),
    Option(name: "Geist Mono", detail: "Bold", source: .file("GeistMono", wght: 700)),
    Option(name: "IBM Plex Mono", detail: "SemiBold", source: .file("IBMPlexMono", wght: nil)),
    Option(name: "Fira Code", detail: "Bold", source: .file("FiraCode", wght: 700)),
    Option(name: "Space Mono", detail: "Bold", source: .file("SpaceMono", wght: nil)),
    Option(name: "Space Grotesk", detail: "Bold", source: .file("SpaceGrotesk", wght: 700)),
    Option(name: "Inter", detail: "Bold", source: .file("Inter", wght: 700)),
    Option(name: "Sora", detail: "Bold", source: .file("Sora", wght: 700)),
    Option(name: "Unbounded", detail: "Medium", source: .file("Unbounded", wght: 500)),
    Option(name: "Fraunces", detail: "SemiBold", source: .file("Fraunces", wght: 600)),
], 2: [
    Option(name: "Current", detail: "hand-drawn strokes", source: .current),
    Option(name: "Unbounded", detail: "Regular", source: .file("Unbounded", wght: 400)),
    Option(name: "Unbounded", detail: "Medium (round 1)", source: .file("Unbounded", wght: 500)),
    Option(name: "Unbounded", detail: "Bold", source: .file("Unbounded", wght: 700)),
    Option(name: "Unbounded", detail: "Black", source: .file("Unbounded", wght: 900)),
    Option(name: "Krona One", detail: "Regular", source: .file("KronaOne", wght: nil)),
    Option(name: "Syne", detail: "ExtraBold", source: .file("Syne", wght: 800)),
    Option(name: "Lexend Exa", detail: "Bold", source: .file("LexendExa", wght: 700)),
    Option(name: "Lexend Giga", detail: "SemiBold", source: .file("LexendGiga", wght: 600)),
    Option(name: "Archivo", detail: "Expanded Bold", source: .file("Archivo", wght: 700, wdth: 125)),
    Option(name: "Encode Sans Expanded", detail: "Bold", source: .file("EncodeSansExpanded", wght: nil)),
    Option(name: "Michroma", detail: "Regular", source: .file("Michroma", wght: nil)),
    Option(name: "Dela Gothic One", detail: "Regular", source: .file("DelaGothicOne", wght: nil)),
    Option(name: "Zen Dots", detail: "Regular", source: .file("ZenDots", wght: nil)),
    Option(name: "Mona Sans", detail: "Expanded Bold", source: .file("MonaSans", wght: 700, wdth: 125)),
    Option(name: "Anybody", detail: "Ultra Wide Bold", source: .file("Anybody", wght: 700, wdth: 150)),
    Option(name: "Goldman", detail: "Bold", source: .file("Goldman", wght: nil)),
    Option(name: "Montserrat", detail: "Bold", source: .file("Montserrat", wght: 700)),
    Option(name: "Red Hat Display", detail: "Black", source: .file("RedHatDisplay", wght: 900)),
]]
let options = rounds[round]!

/// The glyph outline at 1000 pt with its origin at the bounding box's corner. Nil means current.
func outline(_ source: Source) -> CGPath? {
    let font: CTFont
    switch source {
    case .current:
        return nil
    case .file(let name, let wght, let wdth):
        let url = fontsDir.appendingPathComponent(name + ".ttf")
        guard let base = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first else {
            fatalError("cannot read \(url.path)")
        }
        var descriptor = base
        var axes: [NSNumber: NSNumber] = [:]
        if let wght { axes[NSNumber(value: 0x7767_6874)] = NSNumber(value: wght) }  // 'wght'
        if let wdth { axes[NSNumber(value: 0x7764_7468)] = NSNumber(value: wdth) }  // 'wdth'
        if !axes.isEmpty {
            descriptor = CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: axes] as CFDictionary)
        }
        font = CTFontCreateWithFontDescriptor(descriptor, 1000, nil)
    }
    var character: UniChar = 0x4D
    var glyph: CGGlyph = 0
    guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1), let path = CTFontCreatePathForGlyph(font, glyph, nil) else {
        fatalError("no M in \(CTFontCopyPostScriptName(font))")
    }
    return path
}

/// Scaled so every M takes the same room: `height` tall unless that makes it wider than `width`.
func fill(_ glyph: CGPath, in box: CGRect, height: CGFloat, width: CGFloat, color: NSColor, context: CGContext) {
    let bounds = glyph.boundingBoxOfPath
    let scale = min(height / bounds.height, width / bounds.width)
    var transform = CGAffineTransform(translationX: box.midX, y: box.midY)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -bounds.midX, y: -bounds.midY)
    guard let placed = glyph.copy(using: &transform) else { return }
    context.addPath(placed)
    context.setFillColor(color.cgColor)
    context.fillPath()
}

/// The strokes from scripts/make-icon.swift.
func strokeCurrent(in rect: CGRect, color: NSColor) {
    let stroke = NSBezierPath()
    stroke.lineWidth = rect.width * 0.105
    stroke.lineCapStyle = .round
    stroke.lineJoinStyle = .round
    let left = rect.midX - rect.width * 0.25, right = rect.midX + rect.width * 0.25
    let bottom = rect.midY - rect.height * 0.225, top = rect.midY + rect.height * 0.225
    stroke.move(to: NSPoint(x: left, y: bottom))
    stroke.line(to: NSPoint(x: left, y: top))
    stroke.line(to: NSPoint(x: rect.midX, y: bottom + rect.height * 0.16))
    stroke.line(to: NSPoint(x: right, y: top))
    stroke.line(to: NSPoint(x: right, y: bottom))
    color.setStroke()
    stroke.stroke()
}

/// One icon at `size` points with the app icon's grid, ground and hairline.
func drawIcon(_ glyph: CGPath?, at origin: CGPoint, size: CGFloat, context: CGContext) {
    let inset = size * 0.1
    let rect = CGRect(x: origin.x + inset, y: origin.y + inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    putty.setFill()
    path.fill()
    NSColor.black.withAlphaComponent(0.08).setStroke()
    path.lineWidth = size * 0.008
    path.stroke()
    if let glyph {
        fill(glyph, in: rect, height: rect.height * 0.5, width: rect.width * 0.64, color: ink, context: context)
    } else {
        strokeCurrent(in: rect, color: ink)
    }
}

/// The menu bar mark on a strip of menu bar: 10 pt tall inside 18 pt, as StatusMark draws it.
func drawMenuBar(_ glyph: CGPath?, in strip: CGRect, background: NSColor, foreground: NSColor, context: CGContext) {
    background.setFill()
    NSBezierPath(roundedRect: strip, xRadius: 5, yRadius: 5).fill()
    let box = CGRect(x: strip.midX - 10.5, y: strip.midY - 9, width: 21, height: 18)
    if let glyph {
        fill(glyph, in: box, height: 12, width: 14, color: foreground, context: context)
    } else {
        let stroke = NSBezierPath()
        stroke.lineWidth = 2
        stroke.lineCapStyle = .round
        stroke.lineJoinStyle = .round
        let (x, y) = (box.minX, box.minY)
        stroke.move(to: NSPoint(x: x + 5, y: y + 4))
        stroke.line(to: NSPoint(x: x + 5, y: y + 14))
        stroke.line(to: NSPoint(x: x + 10.5, y: y + 7.5))
        stroke.line(to: NSPoint(x: x + 16, y: y + 14))
        stroke.line(to: NSPoint(x: x + 16, y: y + 4))
        foreground.setStroke()
        stroke.stroke()
    }
}

func label(_ text: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]).draw(at: point)
}

let columns = 5
let cellWidth: CGFloat = 268, cellHeight: CGFloat = 352, margin: CGFloat = 40, titleHeight: CGFloat = 76
let rows = Int((Double(options.count) / Double(columns)).rounded(.up))
let boardWidth = margin * 2 + cellWidth * CGFloat(columns)
let boardHeight = margin * 2 + titleHeight + cellHeight * CGFloat(rows)
let scale = 2

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(boardWidth) * scale, pixelsHigh: Int(boardHeight) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: boardWidth, height: boardHeight)
NSGraphicsContext.saveGraphicsState()
let graphics = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = graphics
let context = graphics.cgContext

let background = NSColor(white: 0.965, alpha: 1)
let secondary = NSColor(white: 0.4, alpha: 1)
background.setFill()
NSRect(x: 0, y: 0, width: boardWidth, height: boardHeight).fill()
label("Mestre logo: the M in free fonts", at: CGPoint(x: margin + 14, y: boardHeight - margin - 30), size: 26, weight: .semibold, color: ink)
label("Same ground, ink and icon grid. Round \(round). Each option at 240, 64, 32 and 16 pt, then the menu bar, light and dark.", at: CGPoint(x: margin + 14, y: boardHeight - margin - 54), size: 14, weight: .regular, color: secondary)

for (index, option) in options.enumerated() {
    let glyph = outline(option.source)
    let cellX = margin + CGFloat(index % columns) * cellWidth
    let cellTop = boardHeight - margin - titleHeight - CGFloat(index / columns) * cellHeight
    let x = cellX + 14

    drawIcon(glyph, at: CGPoint(x: x, y: cellTop - 240), size: 240, context: context)

    label(option.name, at: CGPoint(x: x, y: cellTop - 262), size: 14, weight: .semibold, color: ink)
    label(option.detail, at: CGPoint(x: x, y: cellTop - 280), size: 12, weight: .regular, color: secondary)

    let smallBase = cellTop - 342
    drawIcon(glyph, at: CGPoint(x: x, y: smallBase), size: 64, context: context)
    drawIcon(glyph, at: CGPoint(x: x + 66, y: smallBase + 16), size: 32, context: context)
    drawIcon(glyph, at: CGPoint(x: x + 100, y: smallBase + 24), size: 16, context: context)
    drawMenuBar(glyph, in: CGRect(x: x + 124, y: smallBase + 36, width: 96, height: 24), background: NSColor(white: 0.9, alpha: 1), foreground: .black, context: context)
    drawMenuBar(glyph, in: CGRect(x: x + 124, y: smallBase + 6, width: 96, height: 24), background: NSColor(white: 0.13, alpha: 1), foreground: .white, context: context)
}

NSGraphicsContext.restoreGraphicsState()
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try rep.representation(using: .png, properties: [:])!.write(to: outURL)
print("board written to \(outURL.path)")
