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
    // Deep indigo to violet, the "master" purple.
    let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.14, blue: 0.36, alpha: 1), NSColor(calibratedRed: 0.42, green: 0.22, blue: 0.70, alpha: 1)])!
    gradient.draw(in: path, angle: -60)
    // Subtle inner highlight.
    NSColor.white.withAlphaComponent(0.08).setStroke()
    path.lineWidth = s * 0.012
    path.stroke()

    // A command-key-style "M": three strokes, like a baton gesture.
    let stroke = NSBezierPath()
    stroke.lineWidth = s * 0.075
    stroke.lineCapStyle = .round
    stroke.lineJoinStyle = .round
    let left = rect.minX + rect.width * 0.26, right = rect.maxX - rect.width * 0.26
    let bottom = rect.minY + rect.height * 0.30, top = rect.maxY - rect.height * 0.30
    let mid = rect.midX
    stroke.move(to: NSPoint(x: left, y: bottom))
    stroke.line(to: NSPoint(x: left, y: top))
    stroke.line(to: NSPoint(x: mid, y: bottom + rect.height * 0.18))
    stroke.line(to: NSPoint(x: right, y: top))
    stroke.line(to: NSPoint(x: right, y: bottom))
    NSColor.white.setStroke()
    stroke.stroke()
    // A spark above the M: the summoned answer.
    let spark = NSBezierPath()
    let cx = rect.maxX - rect.width * 0.20, cy = rect.maxY - rect.height * 0.20, r = s * 0.045
    spark.move(to: NSPoint(x: cx, y: cy + r)); spark.line(to: NSPoint(x: cx, y: cy - r))
    spark.move(to: NSPoint(x: cx - r, y: cy)); spark.line(to: NSPoint(x: cx + r, y: cy))
    spark.lineWidth = s * 0.03
    spark.lineCapStyle = .round
    NSColor(calibratedRed: 1, green: 0.85, blue: 0.4, alpha: 1).setStroke()
    spark.stroke()
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
