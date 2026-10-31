import AppKit

/// The menu bar icon: always the M, with one dot beside it per active feature. New features
/// raise the count instead of bringing an icon of their own; the tooltip says what's on.
public struct StatusMark: Equatable, Sendable {
    /// Features on right now.
    public let activeCount: Int

    public init(activeCount: Int) {
        self.activeCount = activeCount
    }

    /// As many dots as fit the menu bar's height.
    private static let maxDots = 3
    /// The same width with or without dots, so the items beside it don't shift.
    private static let size = NSSize(width: 21, height: 18)

    public var dots: Int { max(0, min(activeCount, Self.maxDots)) }

    /// A template image, so the menu bar inks it for its own background.
    public var image: NSImage {
        let dots = dots
        let image = NSImage(size: Self.size, flipped: false) { _ in
            NSColor.black.set()
            let path = NSBezierPath()
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let (left, right, bottom, top) = (CGFloat(2), CGFloat(13), CGFloat(4), CGFloat(14))
            path.move(to: NSPoint(x: left, y: bottom))
            path.line(to: NSPoint(x: left, y: top))
            path.line(to: NSPoint(x: (left + right) / 2, y: bottom + 3.5))
            path.line(to: NSPoint(x: right, y: top))
            path.line(to: NSPoint(x: right, y: bottom))
            path.stroke()
            for index in 0..<dots {
                NSBezierPath(ovalIn: NSRect(x: 16.5, y: 11.5 - CGFloat(index) * 4.4, width: 3.2, height: 3.2)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Mestre"
        return image
    }
}
