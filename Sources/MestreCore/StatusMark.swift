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

    /// The M from Archivo Expanded Bold (SIL OFL), as x, y and an optional quadratic control
    /// point, in units of the letter's height. scripts/make-icon.swift holds the same outline.
    private static let outline: [(CGFloat, CGFloat, (CGFloat, CGFloat)?)] = [
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
    private static func fillMark(at origin: NSPoint, height: CGFloat) {
        let path = NSBezierPath()
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x * height, y: origin.y + y * height) }
        for (index, (x, y, control)) in outline.enumerated() {
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

    /// A template image, so the menu bar inks it for its own background.
    public var image: NSImage {
        let dots = dots
        let image = NSImage(size: Self.size, flipped: false) { _ in
            NSColor.black.set()
            Self.fillMark(at: NSPoint(x: 1, y: 4), height: 10)
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
