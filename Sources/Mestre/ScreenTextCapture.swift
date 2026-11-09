import AppKit
import MestreCore

/// Copy Text from Screen: the user drags over a region, Vision reads it on this Mac, the text
/// goes to the clipboard and a toast says how many lines.
///
/// The region is picked by `/usr/sbin/screencapture -i`, the system's own selection (crosshair,
/// Space for a window, Esc to cancel), which writes a PNG into a fresh owner-only temporary
/// folder that is deleted as soon as the image is read. ScreenCaptureKit would need a selection
/// overlay of our own for the same result. Either way macOS ties the capture to Mestre's Screen
/// Recording permission: the first use asks for it (`CGRequestScreenCaptureAccess`); until it is
/// granted the capture shows only the desktop, so the toast says where to allow it.
@MainActor
final class ScreenTextCapture {
    var settings = Config.OCR()
    private var isRunning = false
    private var hasAskedForAccess = false
    private static let accessHint = "Allow Mestre in Privacy & Security › Screen Recording, then try again"

    enum Outcome: Sendable {
        case cancelled
        case text(String, lines: Int)
        case noText
    }

    func start() {
        guard settings.enabled else { NSSound.beep(); return }
        guard !isRunning else { return }
        // First use: ask, and don't capture behind the dialog. A capture without access shows only
        // the desktop, whose labels would be copied as if they were the selection. Later tries go
        // ahead, since macOS may report the grant only after a relaunch.
        if !CGPreflightScreenCaptureAccess(), !hasAskedForAccess {
            hasAskedForAccess = true
            CGRequestScreenCaptureAccess()
            Feedback.toast(Self.accessHint, outsidePanel: .hud(seconds: Feedback.toastSeconds))
            return
        }
        isRunning = true
        let settings = settings
        // A plain queue, not a task: the selection blocks for as long as the user takes.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = Self.capture(settings: settings)
            DispatchQueue.main.async { self?.finish(outcome) }
        }
    }

    private func finish(_ outcome: Outcome) {
        isRunning = false
        switch outcome {
        case .cancelled:
            break
        case .text(let text, let lines):
            // A copy like any other: clipboard history records it (unless an excluded app is in front).
            text.copyToPasteboard(toast: lines == 1 ? "Copied 1 line" : "Copied \(lines) lines", outsidePanel: .hud(seconds: Feedback.toastSeconds))
        case .noText:
            Feedback.toast(CGPreflightScreenCaptureAccess() ? "No text found" : "No text found. " + Self.accessHint, outsidePanel: .hud(seconds: Feedback.toastSeconds))
        }
    }

    /// Blocking: the selection, then the recognition.
    nonisolated private static func capture(settings: Config.OCR) -> Outcome {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("app.mestre.ocr-\(UUID().uuidString)")
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            return .noText
        }
        defer { try? manager.removeItem(at: folder) }
        let file = folder.appendingPathComponent("selection.png")
        // -i: interactive selection, -x: no sound, -o: no window shadow, -t png.
        _ = ProcessRunner.capture("/usr/sbin/screencapture", ["-i", "-x", "-o", "-t", "png", file.path])
        guard manager.fileExists(atPath: file.path) else { return .cancelled }  // Esc leaves no file
        guard let lines = (try? TextRecognition.lines(at: file, settings: settings)) ?? nil, !lines.isEmpty else { return .noText }
        return .text(TextRecognition.join(lines, keepLineBreaks: settings.keepLineBreaks), lines: lines.count)
    }
}
