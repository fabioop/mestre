import Foundation
import MestreCore
import os

/// Reads the text in clipboard-history images (`ocr.clipboardImages`): one at a time on a
/// background-priority queue, each image once, then hands the text back on the main thread.
@MainActor
final class ClipboardTextReader {
    private let directory: URL
    /// `isLast`: nothing else is queued, so a backlog refreshes the results once, not per image.
    private let onRead: (_ name: String, _ text: String?, _ isLast: Bool) -> Void
    private let queue = DispatchQueue(label: "app.mestre.clipboard.ocr", qos: .background)
    /// Names queued or being read, so an image is never read twice at once.
    private var queued = Set<String>()
    /// Names Vision failed on: not tried again until the settings change or Mestre restarts,
    /// so a broken image doesn't cost a read on every later copy.
    private var failed = Set<String>()
    /// Bumped by `cancelAll`; a job queued under an older value is skipped.
    private let generation = OSAllocatedUnfairLock(initialState: 0)

    init(directory: URL, onRead: @escaping (_ name: String, _ text: String?, _ isLast: Bool) -> Void) {
        self.directory = directory
        self.onRead = onRead
    }

    /// `maxBytes`: `clipboard.maxTextBytes`, the cap on what one entry keeps (Copy Text copies it all).
    func enqueue(_ names: [String], settings: Config.OCR, maxBytes: Int) {
        let generation = generation
        let current = generation.withLock { $0 }
        for name in names where ClipboardEntry.isImageName(name) && !queued.contains(name) && !failed.contains(name) {
            queued.insert(name)
            let url = directory.appendingPathComponent(name)
            queue.async { [weak self] in
                guard generation.withLock({ $0 }) == current else { return }
                let text = Self.read(url, settings: settings, maxBytes: maxBytes)
                DispatchQueue.main.async {
                    guard let self, generation.withLock({ $0 }) == current else { return }
                    self.queued.remove(name)
                    if text == nil { self.failed.insert(name) }
                    self.onRead(name, text, self.queued.isEmpty)
                }
            }
        }
    }

    /// Drops whatever is queued (OCR settings changed, OCR turned off); failed images get
    /// another try under the new settings.
    func cancelAll() {
        generation.withLock { $0 &+= 1 }
        queued.removeAll()
        failed.removeAll()
    }

    /// The image's text, "" when it has none or isn't an image (neither is tried again), nil when
    /// Vision failed (tried again after a settings change or a restart). Kept to `maxBytes`;
    /// only its head is searched (`ClipboardEntry.recognizedSearchLength`).
    nonisolated private static func read(_ url: URL, settings: Config.OCR, maxBytes: Int) -> String? {
        let lines: [String]?
        do { lines = try TextRecognition.lines(at: url, settings: settings) } catch { return nil }
        // History always keeps the lines: they're what the subtitle and Copy Text show.
        return lines.map { TextRecognition.join($0, keepLineBreaks: true).prefix(utf8Bytes: maxBytes) } ?? ""
    }
}
