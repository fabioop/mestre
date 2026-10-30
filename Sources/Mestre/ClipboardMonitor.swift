import AppKit
import MestreCore

/// Watches the general pasteboard and keeps the history on disk. There is no
/// notification for pasteboard changes, so this polls `changeCount` (an integer
/// read, no data copy) at a configurable interval, like every clipboard manager.
/// Image encoding and all file I/O happen off the main thread.
@MainActor
final class ClipboardMonitor {
    private(set) var history = ClipboardHistory()
    /// Fires after a background capture or expiry changed the history.
    var onChange: (() -> Void)?

    var settings = Config.Clipboard() {
        didSet {
            if settings.enabled != oldValue.enabled || settings.pollIntervalSeconds != oldValue.pollIntervalSeconds { restartTimer() }
            if !settings.enabled { removeAll() }
            expire()
        }
    }

    let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("history.json") }
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    /// The app that was in front at the previous poll: a copy made just before switching
    /// apps is attributed to it, not to the app that is in front now.
    private var previousFrontApp: NSRunningApplication?
    private let images = NSCache<NSString, NSImage>()
    private let io = DispatchQueue(label: "app.mestre.clipboard", qos: .utility)  // serial: writes land in order
    private var pendingWrite: DispatchWorkItem?

    nonisolated static let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Mestre/Clipboard")

    init(directory: URL = ClipboardMonitor.defaultDirectory) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(ClipboardHistory.self, from: data) {
            history = saved
        }
        restartTimer()
    }

    // MARK: Using entries

    /// Puts an entry back on the pasteboard without recording it as new.
    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        switch entry.kind {
        case .text:
            write(entry.content)
        case .files:
            pasteboard.clearContents()
            pasteboard.writeObjects(entry.content.split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) as NSURL })
        case .image:
            guard let image = image(for: entry) else { NSSound.beep(); return }
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
        lastChangeCount = pasteboard.changeCount  // our own write is not a new entry
        history.touch(id: entry.id)
        persist()
    }

    /// Puts text on the pasteboard without recording it (history entries, snippets).
    func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    /// Records whatever is on the pasteboard right now, before Mestre overwrites it.
    func captureNow() {
        if settings.enabled { poll() }
    }

    func remove(_ entry: ClipboardEntry) {
        if let removed = history.remove(id: entry.id) { deleteImage(removed) }
        persist()
    }

    func removeAll() {
        for entry in history.removeAll() { deleteImage(entry) }
        persist()
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard entry.kind == .image else { return nil }
        if let cached = images.object(forKey: entry.content as NSString) { return cached }
        guard let image = NSImage(contentsOf: directory.appendingPathComponent(entry.content)) else { return nil }
        images.setObject(image, forKey: entry.content as NSString)
        return image
    }

    // MARK: Polling

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard settings.enabled else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        previousFrontApp = NSWorkspace.shared.frontmostApplication
        let timer = Timer(timeInterval: settings.pollIntervalSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = settings.pollIntervalSeconds / 2  // lets the system coalesce wakeups
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let front = NSWorkspace.shared.frontmostApplication
        defer { previousFrontApp = front }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        // Password managers mark their contents; honour that, and their bundle ids.
        let types = pasteboard.types ?? []
        if types.contains(where: { Self.concealedTypes.contains($0.rawValue) }) { return }
        let candidates = [front, previousFrontApp].compactMap { $0?.bundleIdentifier }
        if candidates.contains(where: { id in settings.excludeApps.contains { $0.caseInsensitiveCompare(id) == .orderedSame } }) { return }

        capture(from: pasteboard, source: front?.localizedName)
    }

    static let concealedTypes = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]

    /// Reads the pasteboard on the main thread (required), then does any heavy work off it.
    private func capture(from pasteboard: NSPasteboard, source: String?) {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            record(ClipboardEntry(kind: .files, content: urls.map(\.path).joined(separator: "\n"), sourceApp: source))
            return
        }
        if let text = pasteboard.string(forType: .string) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= settings.maxTextBytes else { return }
            record(ClipboardEntry(kind: .text, content: text, sourceApp: source))
            return
        }
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else { return }
        let directory = directory
        io.async { [weak self] in
            // Normalise to PNG; the name is the content hash so repeats are one entry.
            guard !data.isEmpty, let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return }
            let name = ClipboardEntry.imageName(for: png)
            do { try png.write(to: directory.appendingPathComponent(name), options: .atomic) } catch { return }
            DispatchQueue.main.async { self?.record(ClipboardEntry(kind: .image, content: name, sourceApp: source)) }
        }
    }

    private func record(_ entry: ClipboardEntry) {
        if let dropped = history.add(entry, limit: settings.maxItems) { deleteImage(dropped) }
        expire()
        persist()
        onChange?()
    }

    private func expire() {
        let expired = history.expire(olderThan: settings.maxAgeDays * 86_400)
        for entry in expired { deleteImage(entry) }
        if !expired.isEmpty { persist() }
    }

    // MARK: Persistence (serial queue, debounced, owner-only file)

    private func persist() {
        pendingWrite?.cancel()
        let snapshot = history
        let url = fileURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        pendingWrite = work
        io.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func deleteImage(_ entry: ClipboardEntry) {
        guard entry.kind == .image, !history.entries.contains(where: { $0.content == entry.content }) else { return }
        images.removeObject(forKey: entry.content as NSString)
        let url = directory.appendingPathComponent(entry.content)
        io.async { try? FileManager.default.removeItem(at: url) }
    }
}
