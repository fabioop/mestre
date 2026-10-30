import Foundation

/// Where a window should go, relative to its screen's visible area.
public enum WindowLayout: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, almostMaximize, center, restore
    case nextDisplay, previousDisplay

    public var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .leftThird: return "Left Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two Thirds"
        case .rightTwoThirds: return "Right Two Thirds"
        case .topLeft: return "Top Left Quarter"
        case .topRight: return "Top Right Quarter"
        case .bottomLeft: return "Bottom Left Quarter"
        case .bottomRight: return "Bottom Right Quarter"
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        case .center: return "Center"
        case .restore: return "Restore"
        case .nextDisplay: return "Next Display"
        case .previousDisplay: return "Previous Display"
        }
    }

    public var symbol: String {
        switch self {
        case .leftHalf, .leftThird, .leftTwoThirds: return "rectangle.lefthalf.inset.filled"
        case .rightHalf, .rightThird, .rightTwoThirds: return "rectangle.righthalf.inset.filled"
        case .topHalf, .topLeft, .topRight: return "rectangle.tophalf.inset.filled"
        case .bottomHalf, .bottomLeft, .bottomRight: return "rectangle.bottomhalf.inset.filled"
        case .centerThird, .center: return "rectangle.center.inset.filled"
        case .maximize, .almostMaximize: return "rectangle.inset.filled"
        case .restore: return "arrow.uturn.backward"
        case .nextDisplay, .previousDisplay: return "display.2"
        }
    }

    /// Defaults on the ⌃⌥ layer, the common window-management convention.
    public var defaultHotkey: String? {
        switch self {
        case .leftHalf: return "ctrl+option+left"
        case .rightHalf: return "ctrl+option+right"
        case .topHalf: return "ctrl+option+up"
        case .bottomHalf: return "ctrl+option+down"
        case .leftThird: return "ctrl+option+d"
        case .centerThird: return "ctrl+option+f"
        case .rightThird: return "ctrl+option+g"
        case .leftTwoThirds: return "ctrl+option+e"
        case .rightTwoThirds: return "ctrl+option+t"
        case .topLeft: return "ctrl+option+u"
        case .topRight: return "ctrl+option+i"
        case .bottomLeft: return "ctrl+option+j"
        case .bottomRight: return "ctrl+option+k"
        case .maximize: return "ctrl+option+return"
        case .almostMaximize: return "ctrl+option+shift+return"
        case .center: return "ctrl+option+c"
        case .restore: return "ctrl+option+delete"
        case .nextDisplay: return "ctrl+option+cmd+right"
        case .previousDisplay: return "ctrl+option+cmd+left"
        }
    }
}

public extension WindowLayout {
    /// The ⌃⌥ layer as hotkey-table defaults: combo → "window:<layout>".
    static var defaultHotkeys: [String: String] {
        Dictionary(uniqueKeysWithValues: allCases.compactMap { layout in layout.defaultHotkey.map { ($0, "window:" + layout.rawValue) } })
    }
}

/// Pure frame maths in a top-left-origin coordinate space (what the Accessibility
/// API uses). `screen` is the screen's usable area, already excluding menu bar and Dock.
public enum WindowGeometry {
    /// The frame for `layout`, or nil for layouts that aren't a fixed rectangle (restore, displays).
    public static func frame(for layout: WindowLayout, in screen: CGRect, current: CGRect, gap: CGFloat = 0) -> CGRect? {
        let s = screen.insetBy(dx: gap, dy: gap)
        let w = s.width, h = s.height
        let third = (w - gap * 2) / 3
        let halfW = (w - gap) / 2, halfH = (h - gap) / 2
        switch layout {
        case .leftHalf: return CGRect(x: s.minX, y: s.minY, width: halfW, height: h)
        case .rightHalf: return CGRect(x: s.maxX - halfW, y: s.minY, width: halfW, height: h)
        case .topHalf: return CGRect(x: s.minX, y: s.minY, width: w, height: halfH)
        case .bottomHalf: return CGRect(x: s.minX, y: s.maxY - halfH, width: w, height: halfH)
        case .leftThird: return CGRect(x: s.minX, y: s.minY, width: third, height: h)
        case .centerThird: return CGRect(x: s.minX + third + gap, y: s.minY, width: third, height: h)
        case .rightThird: return CGRect(x: s.maxX - third, y: s.minY, width: third, height: h)
        case .leftTwoThirds: return CGRect(x: s.minX, y: s.minY, width: third * 2 + gap, height: h)
        case .rightTwoThirds: return CGRect(x: s.maxX - third * 2 - gap, y: s.minY, width: third * 2 + gap, height: h)
        case .topLeft: return CGRect(x: s.minX, y: s.minY, width: halfW, height: halfH)
        case .topRight: return CGRect(x: s.maxX - halfW, y: s.minY, width: halfW, height: halfH)
        case .bottomLeft: return CGRect(x: s.minX, y: s.maxY - halfH, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: s.maxX - halfW, y: s.maxY - halfH, width: halfW, height: halfH)
        case .maximize: return s
        case .almostMaximize: return s.insetBy(dx: w * 0.05, dy: h * 0.05)
        case .center: return CGRect(x: s.midX - current.width / 2, y: s.midY - current.height / 2, width: current.width, height: current.height)
        case .restore, .nextDisplay, .previousDisplay: return nil
        }
    }

    /// What applying `layout` to a window at `current` on `screen` should do.
    public enum Target: Equatable {
        case frame(CGRect)
        case restore
        case nothing
    }

    /// Resolves a layout to a concrete frame, including cycling and display moves.
    /// `screens` is every screen's usable area, ordered; `tolerance` absorbs windows that
    /// snap to resize increments.
    public static func target(for layout: WindowLayout, current: CGRect, screen: CGRect, screens: [CGRect], gap: CGFloat, tolerance: CGFloat = 12) -> Target {
        switch layout {
        case .restore:
            return .restore
        case .nextDisplay, .previousDisplay:
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return .nothing }
            let destination = screens[(index + (layout == .nextDisplay ? 1 : screens.count - 1)) % screens.count]
            return .frame(move(current, from: screen, to: destination))
        default:
            let step = next(in: cycle(for: layout), current: current, screen: screen, gap: gap, tolerance: tolerance)
            return frame(for: step, in: screen, current: current, gap: gap).map { .frame($0) } ?? .nothing
        }
    }

    /// Pressing the same left/right shortcut again steps through widths: half → two thirds → third.
    public static func cycle(for layout: WindowLayout) -> [WindowLayout] {
        switch layout {
        case .leftHalf: return [.leftHalf, .leftTwoThirds, .leftThird]
        case .rightHalf: return [.rightHalf, .rightTwoThirds, .rightThird]
        default: return [layout]
        }
    }

    /// The layout to apply when `layout` is requested and the window is already at
    /// one of its cycle steps: the next step, wrapping around.
    public static func next(in cycle: [WindowLayout], current: CGRect, screen: CGRect, gap: CGFloat = 0, tolerance: CGFloat = 2) -> WindowLayout {
        guard cycle.count > 1 else { return cycle[0] }
        for (index, step) in cycle.enumerated() {
            if let frame = frame(for: step, in: screen, current: current, gap: gap), frame.isApproximately(current, tolerance: tolerance) {
                return cycle[(index + 1) % cycle.count]
            }
        }
        return cycle[0]
    }

    /// Moves `current` onto `target` screen keeping its relative position and size (clamped
    /// to fit). A window that filled its screen fills the new one.
    public static func move(_ current: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        if current.isApproximately(source, tolerance: 2) { return target }
        let width = min(current.width, target.width)
        let height = min(current.height, target.height)
        func ratio(_ offset: CGFloat, _ room: CGFloat) -> CGFloat { room > 0 ? min(1, max(0, offset / room)) : 0 }
        let relX = ratio(current.minX - source.minX, source.width - current.width)
        let relY = ratio(current.minY - source.minY, source.height - current.height)
        return CGRect(x: target.minX + relX * (target.width - width), y: target.minY + relY * (target.height - height), width: width, height: height)
    }
}

public extension CGRect {
    func isApproximately(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
