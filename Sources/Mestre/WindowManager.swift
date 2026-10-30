import AppKit
import ApplicationServices
import MestreCore

/// Moves and resizes the focused window of the frontmost app through the
/// Accessibility API. Needs the Accessibility permission; `apply` never prompts,
/// the host does that once with `ensurePermission`.
@MainActor
final class WindowManager {
    enum Failure: Error { case noPermission, noWindow, noScreen }

    var gap: CGFloat = 0

    /// Frames before the first layout, keyed by window identity, most recent last.
    private var originals: [(key: String, frame: CGRect)] = []
    /// The frame we last set per window: if the window moved since, the user did it,
    /// and that position becomes the new restore point.
    private var applied: [String: CGRect] = [:]
    /// The app that was frontmost before Mestre activated (Settings, alerts).
    private var lastOtherApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.lastOtherApp = app }
        }
    }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt (once; macOS remembers the answer).
    @discardableResult
    static func ensurePermission() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func apply(_ layout: WindowLayout) throws {
        guard Self.hasPermission else { throw Failure.noPermission }
        guard let window = targetWindow(), let current = AX.frame(of: window) else { throw Failure.noWindow }
        let screens = Self.screensInAXSpace()
        guard let screen = Self.screen(containing: current, in: screens) else { throw Failure.noScreen }
        let key = AX.identity(of: window)

        switch WindowGeometry.target(for: layout, current: current, screen: screen, screens: screens, gap: gap) {
        case .nothing:
            return
        case .restore:
            guard let index = originals.lastIndex(where: { $0.key == key }) else { NSSound.beep(); return }
            let original = originals.remove(at: index).frame
            applied[key] = nil
            AX.setFrame(original, of: window)
        case .frame(let frame):
            rememberOriginal(current, for: key)
            AX.setFrame(frame, of: window)
            applied[key] = frame
        }
    }

    /// Records the pre-layout frame once per window, refreshing it when the user has
    /// moved the window since the last layout. Bounded, oldest first out.
    private func rememberOriginal(_ frame: CGRect, for key: String) {
        let movedByUser = applied[key].map { !$0.isApproximately(frame, tolerance: 12) } ?? true
        if let index = originals.firstIndex(where: { $0.key == key }) {
            if movedByUser { originals[index].frame = frame }
        } else {
            originals.append((key, frame))
            if originals.count > 32 { originals.removeFirst() }
        }
    }

    // MARK: Accessibility plumbing

    /// The focused window of the frontmost app, or of the app that was frontmost before
    /// Mestre took the front (so the Settings window never gets snapped). Sheets and
    /// system dialogs are skipped.
    private func targetWindow() -> AXUIElement? {
        var app = NSWorkspace.shared.frontmostApplication
        if app?.processIdentifier == ProcessInfo.processInfo.processIdentifier { app = lastOtherApp }
        guard let app, let window = AX.element(kAXFocusedWindowAttribute, of: AX.application(app.processIdentifier)) else { return nil }
        if let subrole = AX.string(kAXSubroleAttribute, of: window), ["AXSheet", "AXSystemDialog"].contains(subrole) { return nil }
        return window
    }

    /// Visible screen frames in the Accessibility coordinate space (origin at the top-left
    /// of the main screen, y growing downwards), ordered left to right, then top to bottom.
    static func screensInAXSpace() -> [CGRect] {
        guard let main = NSScreen.screens.first else { return [] }
        return NSScreen.screens
            .map { screen in
                let visible = screen.visibleFrame
                return CGRect(x: visible.minX, y: main.frame.maxY - visible.maxY, width: visible.width, height: visible.height)
            }
            .sorted { $0.minX != $1.minX ? $0.minX < $1.minX : $0.minY < $1.minY }
    }

    /// The screen holding the window's centre, else the one it overlaps most, else the first.
    private static func screen(containing frame: CGRect, in screens: [CGRect]) -> CGRect? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let hit = screens.first(where: { $0.contains(center) }) { return hit }
        func overlap(_ screen: CGRect) -> CGFloat {
            let i = screen.intersection(frame)
            return i.isNull ? 0 : i.width * i.height
        }
        return screens.filter { overlap($0) > 0 }.max { overlap($0) < overlap($1) } ?? screens.first
    }
}
