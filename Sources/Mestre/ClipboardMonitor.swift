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

    /// The `ocr` section: whether images in the history get their text read.
    var ocr = Config.OCR() {
        didSet {
            if Self.readerSettings(ocr) != Self.readerSettings(oldValue) {
                textReader.cancelAll()
                if unsavedText { persist() }
            }
            readPendingText()  // also the first assignment, at launch: queued names aren't queued twice
        }
    }
    private lazy var textReader = ClipboardTextReader(directory: directory) { [weak self] name, text, isLast in
        self?.storeText(text, forImage: name, notify: isLast)
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
    /// history.json is read off the main thread at launch; nothing is written before it landed.
    private var loaded = false
    /// Text read since the last write: a backlog of images is written once, when it finishes.
    private var unsavedText = false
    /// Removals made while history.json was still being read, applied to it when it lands.
    private var removedBeforeLoad = Set<UUID>()
    private var clearedBeforeLoad = false

    nonisolated static let defaultDirectory = AppSupport.folder.appendingPathComponent("Clipboard")

    init(directory: URL = ClipboardMonitor.defaultDirectory) {
        self.directory = directory
        restartTimer()
        load()
    }

    /// Reads and decodes history.json (and derives every entry's search text) on the I/O queue.
    private func load() {
        let url = fileURL
        let directory = directory
        io.async { [weak self] in
            AppSupport.makePrivateFolder(directory)
            let saved = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ClipboardHistory.self, from: $0) }
            DispatchQueue.main.async { self?.finishLoading(saved ?? ClipboardHistory()) }
        }
    }

    /// Installs the saved history, keeping anything copied while it was being read.
    private func finishLoading(_ saved: ClipboardHistory) {
        let copiedMeanwhile = history.entries
        history = saved
        loaded = true
        let undone = clearedBeforeLoad || !removedBeforeLoad.isEmpty
        if clearedBeforeLoad { for entry in history.removeAll() { deleteImage(entry) } }
        for id in removedBeforeLoad { if let removed = history.remove(id: id) { deleteImage(removed) } }
        clearedBeforeLoad = false
        removedBeforeLoad = []
        for entry in copiedMeanwhile.reversed() {
            if let dropped = history.add(entry, limit: settings.maxItems) { deleteImage(dropped) }
        }
        removeOrphanImages()
        if !settings.enabled {
            removeAll()
        } else {
            expire()
            if undone || !copiedMeanwhile.isEmpty { persist() }
        }
        readPendingText()
        onChange?()
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

    /// Puts text on the pasteboard without recording it (history entries, snippets). `transient`
    /// marks it as Mestre's own, so other clipboard managers skip it too.
    func write(_ text: String, transient: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if transient {
            for type in ["org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
                pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(type))
            }
        }
        lastChangeCount = pasteboard.changeCount
        Self.ownTransientChange = transient ? pasteboard.changeCount : nil
    }

    /// Records whatever is on the pasteboard right now, before Mestre overwrites it.
    func captureNow() {
        if settings.enabled { poll() }
    }

    func remove(_ entry: ClipboardEntry) {
        if !loaded { removedBeforeLoad.insert(entry.id) }
        if let removed = history.remove(id: entry.id) { deleteImage(removed) }
        persist()
    }

    func removeAll() {
        if !loaded { clearedBeforeLoad = true }
        for entry in history.removeAll() { deleteImage(entry) }
        persist()
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard entry.kind == .image, ClipboardEntry.isImageName(entry.content) else { return nil }
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

    /// The nspasteboard.org markers, plus older ones some password managers and tools still use.
    nonisolated static let concealedTypes = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType", "Pasteboard generator type",
        "com.typeit4me.clipping", "net.antelle.keeweb",
    ]

    /// The pasteboard's change count after Mestre's last transient write. That paste carries the
    /// transient markers too, yet a snippet's `{clipboard}` may use it: it is Mestre's own text.
    private(set) static var ownTransientChange: Int?

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
            do { try AppSupport.writePrivately(png, to: directory.appendingPathComponent(name)) } catch { return }
            DispatchQueue.main.async { self?.record(ClipboardEntry(kind: .image, content: name, sourceApp: source)) }
        }
    }

    private func record(_ entry: ClipboardEntry) {
        if let dropped = history.add(entry, limit: settings.maxItems) { deleteImage(dropped) }
        expire()
        persist()
        onChange?()
        if entry.kind == .image { readPendingText(only: entry.content) }
    }

    // MARK: Text in images (background, once per image)

    /// Queues the images whose text hasn't been read: the whole backlog (at launch, after a
    /// settings change), or only `name`, a new copy.
    private func readPendingText(only name: String? = nil) {
        guard settings.enabled, ocr.readsClipboardImages else { return }
        var names = history.imagesAwaitingText
        if let name { names = names.contains(name) ? [name] : [] }
        if !names.isEmpty { textReader.enqueue(names, settings: ocr, maxBytes: settings.maxTextBytes) }
    }

    /// What the clipboard reader's results depend on; `keepLineBreaks` is Copy Text from
    /// Screen's alone, so changing it leaves the queue as it is.
    private static func readerSettings(_ ocr: Config.OCR) -> (Bool, [String], Config.OCR.Level, Int) {
        (ocr.readsClipboardImages, ocr.languages, ocr.recognitionLevel, ocr.maxImagePixels)
    }

    private func storeText(_ text: String?, forImage name: String, notify isLast: Bool) {
        guard ocr.readsClipboardImages else { return }
        if let text, history.setRecognizedText(text, forImage: name) { unsavedText = true }
        guard isLast else { return }
        if unsavedText { persist() }
        onChange?()
    }

    private func expire() {
        let expired = history.expire(olderThan: settings.maxAgeDays * 86_400)
        for entry in expired { deleteImage(entry) }
        if !expired.isEmpty { persist() }
    }

    // MARK: Persistence (serial queue, debounced, owner-only file)

    private func persist() {
        guard loaded else { return }
        unsavedText = false
        pendingWrite?.cancel()
        let snapshot = history
        let url = fileURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? AppSupport.writePrivately(data, to: url)
        }
        pendingWrite = work
        io.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Images no entry names any more (a history that failed to load, a crash between writes), so
    /// clearing the history or `maxAgeDays` really removes every copied image.
    private func removeOrphanImages() {
        let kept = Set(history.entries.filter { $0.kind == .image }.map(\.content))
        let directory = directory
        io.async {
            let manager = FileManager.default
            for name in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? [] where ClipboardEntry.isImageName(name) && !kept.contains(name) {
                try? manager.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    private func deleteImage(_ entry: ClipboardEntry) {
        // The name comes from history.json; anything but a content hash could point outside the folder.
        guard entry.kind == .image, ClipboardEntry.isImageName(entry.content),
              !history.entries.contains(where: { $0.content == entry.content }) else { return }
        images.removeObject(forKey: entry.content as NSString)
        let url = directory.appendingPathComponent(entry.content)
        io.async { try? FileManager.default.removeItem(at: url) }
    }
}
