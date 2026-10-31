// Draws the Mestre app icon with CoreGraphics and writes an iconset.
// Usage: swift scripts/make-icon.swift <iconset dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

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

    // The M, in the proportions of the menu bar capsule: the same mark at both sizes.
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
    NSColor(srgbRed: 0.114, green: 0.114, blue: 0.106, alpha: 1).setStroke()
    stroke.stroke()
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
