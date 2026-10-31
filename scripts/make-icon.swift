// Draws the Mestre app icon with CoreGraphics and writes an iconset.
// Usage: swift scripts/make-icon.swift <iconset dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// The M from Archivo Expanded Bold (SIL OFL), as x, y and an optional quadratic control point,
/// in units of the letter's height. Sources/MestreCore/StatusMark.swift holds the same outline.
let markOutline: [(CGFloat, CGFloat, (CGFloat, CGFloat)?)] = [
    (0.0000, 0.0000, nil), (0.0000, 1.0000, nil), (0.3915, 1.0000, nil), (0.5972, 0.5183, nil),
    (0.6233, 0.4523, (0.6077, 0.4934)), (0.6555, 0.3665, (0.6389, 0.4111)), (0.6851, 0.2860, (0.6721, 0.3220)),
    (0.6953, 0.2860, nil),
    (0.7232, 0.3606, (0.7071, 0.3182)), (0.7556, 0.4450, (0.7392, 0.4030)), (0.7836, 0.5160, (0.7719, 0.4871)),
    (0.9892, 1.0000, nil), (1.3712, 1.0000, nil), (1.3712, 0.0000, nil), (1.1200, 0.0000, nil), (1.1200, 0.5732, nil),
    (1.1208, 0.6339, (1.1200, 0.6005)), (1.1229, 0.6998, (1.1215, 0.6673)), (1.1255, 0.7560, (1.1244, 0.7323)),
    (1.1139, 0.7560, nil),
    (1.0939, 0.6981, (1.1060, 0.7317)), (1.0696, 0.6313, (1.0817, 0.6645)), (1.0470, 0.5732, (1.0575, 0.5981)),
    (0.7999, 0.0000, nil), (0.5621, 0.0000, nil), (0.3138, 0.5732, nil),
    (0.2871, 0.6405, (0.3001, 0.6061)), (0.2641, 0.7056, (0.2741, 0.6750)), (0.2469, 0.7560, (0.2542, 0.7362)),
    (0.2353, 0.7560, nil),
    (0.2375, 0.7067, (0.2368, 0.7373)), (0.2389, 0.6417, (0.2382, 0.6761)), (0.2397, 0.5732, (0.2397, 0.6072)),
    (0.2397, 0.0000, nil),
]

/// Fills the M with its corner at `origin`, `height` tall and 1.3712 × `height` wide.
func fillMark(at origin: NSPoint, height: CGFloat) {
    let path = NSBezierPath()
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x * height, y: origin.y + y * height) }
    for (index, (x, y, control)) in markOutline.enumerated() {
        if index == 0 {
            path.move(to: point(x, y))
        } else if let control {
            path.curve(to: point(x, y), controlPoint: point(control.0, control.1))
        } else {
            path.line(to: point(x, y))
        }
    }
    path.close()
    path.fill()
}

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size
    // macOS icon grid: the rounded square covers ~80% of the canvas.
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    // Putty, the ground of the theme of the same name.
    NSColor(srgbRed: 0.863, green: 0.855, blue: 0.824, alpha: 1).setFill()
    path.fill()
    // A hairline, so the edge holds on a light background.
    NSColor.black.withAlphaComponent(0.08).setStroke()
    path.lineWidth = s * 0.008
    path.stroke()

    // The M, the same outline as the menu bar's.
    let height = rect.width * 0.64 / 1.3712
    NSColor(srgbRed: 0.114, green: 0.114, blue: 0.106, alpha: 1).setFill()
    fillMark(at: NSPoint(x: rect.midX - rect.width * 0.32, y: rect.midY - height / 2), height: height)
    image.unlockFocus()
    return image
}

func write(_ image: NSImage, _ name: String, _ px: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let image = draw(size: CGFloat(points))
    write(image, "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png", points * scale)
}
print("iconset written to \(out.path)")
