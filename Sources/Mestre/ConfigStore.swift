import AppKit
import Combine
import Foundation
import MestreCore

/// Owns the config file: reads it at launch, writes it when the app changes a
/// setting, and watches it so edits made in a text editor apply immediately.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: Config {
        didSet {
            if config.keys != oldValue.keys { rebuildKeyBindings() }
            if config.hotkeys != oldValue.hotkeys || config.hotKey != oldValue.hotKey || config.windows.enabled != oldValue.windows.enabled {
                hotkeyTable = HotkeyTable(hotkeys: config.hotkeys, defaults: config.hotkeyDefaults, panelHotKey: config.hotKey)
            }
            if config != lastPersisted { save() }
        }
    }
    /// Parsed once per change to `config.keys` or the action table; the panel and Settings read this.
    @Published private(set) var keyBindings: KeyBindings = .empty
    /// Every action the panel knows, collected from the providers at launch; the Keys page lists it.
    @Published var actionTable = ActionTable() {
        didSet { rebuildKeyBindings() }
    }
    /// Set when the file exists but can't be parsed; the previous config stays in effect.
    @Published private(set) var loadError: String?

    // Transient UI state, not persisted.
    @Published var isRecordingHotKey = false
    /// Parsed `hotkeys` section, rebuilt with the config.
    @Published private(set) var hotkeyTable = HotkeyTable(hotkeys: [:], defaults: [:], panelHotKey: .default)
    /// Why the panel hotkey could not be registered, if it couldn't.
    @Published var hotKeyError: String?
    /// Hotkeys that failed, keyed by the config's own spelling.
    @Published var hotkeyErrors: [String: String] = [:]

    let fileURL: URL
    /// The path with the home folder as "~", for display.
    var displayPath: String { fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
    private var lastPersisted: Config
    private var watcher: DirectoryWatcher?
    private var fileWatcher: FileWatcher?

    /// $XDG_CONFIG_HOME/mestre/config.json, defaulting to ~/.config/mestre/config.json.
    nonisolated static var defaultFileURL: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? NSHomeDirectory() + "/.config"
        return URL(fileURLWithPath: base).appendingPathComponent("mestre/config.json")
    }

    init(fileURL: URL = ConfigStore.defaultFileURL) {
        self.fileURL = fileURL
        let initial = Self.read(from: fileURL)
        switch initial {
        case .success(let loaded, let notes):
            config = loaded
            self.notes = notes
            lastPersisted = loaded
        case .failure(let error):
            config = Config()
            lastPersisted = Config()
            loadError = error.localizedDescription
            NSLog("Config: %@", error.localizedDescription)
        case .missing:
            config = Config()
            lastPersisted = Config()
            // First launch: a file of notes only, so every key keeps its documented default until
            // the user writes one (`mestre --show-config --default --docs` prints them all).
            let starter = ConfigDocs.starterFile()
            notes = ((try? JSONSerialization.jsonObject(with: Data(starter.utf8)) as? [String: Any]) ?? [:])
            write(Data(starter.utf8))
        }
        // The file is written only when a setting changes: a key that is missing keeps its default.
        rebuildKeyBindings()
        hotkeyTable = HotkeyTable(hotkeys: config.hotkeys, defaults: config.hotkeyDefaults, panelHotKey: config.hotKey)
        startWatching()
    }

    private func rebuildKeyBindings() {
        keyBindings = KeyBindings(keys: config.keys, actions: actionTable)
    }

    func openInEditor() {
        NSWorkspace.shared.open(fileURL)
    }

    /// Every default with its note, written to a temporary file and opened beside the user's file.
    static func showDefaults() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("mestre-defaults.json")
            try ConfigDocs.dump(Config(), docs: true).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            NSLog("Config: failed to write the defaults: %@", error.localizedDescription)
        }
    }

    // MARK: Reading and writing

    private enum ReadResult {
        case success(Config, notes: [String: Any]), failure(Error), missing
    }

    /// The file's `_…` keys, kept so a save writes them back above the settings.
    private var notes: [String: Any] = [:]

    private static func read(from url: URL) -> ReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            let notes = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]).filter { $0.key.hasPrefix("_") }
            return .success(try JSONDecoder().decode(Config.self, from: data), notes: notes)
        } catch {
            return .failure(error)
        }
    }

    /// Never overwrites a file that didn't parse: it is the user's, probably mid-edit, and the
    /// in-memory config is not what they wrote. Settings shows the error until the file is fixed.
    /// Writes only what differs from the defaults, under the file's own notes, so an untouched
    /// key keeps following its default in later versions.
    private func save() {
        guard loadError == nil, let changes = try? ConfigDocs.changes(in: config) else { return }
        if write(Data(ConfigDocs.file(changes: changes, notes: notes).utf8)) { lastPersisted = config }
    }

    /// Writes the file atomically, creating the folder on the way. False (and a log line) on failure.
    @discardableResult
    private func write(_ data: Data) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            NSLog("Config: failed to write %@: %@", fileURL.path, error.localizedDescription)
            return false
        }
    }

    /// The file as it is, with no side effects: for `--show-config`.
    static func readCurrent() -> Config {
        if case .success(let config, _) = read(from: defaultFileURL) { return config }
        return Config()
    }

    // MARK: Watching

    private func startWatching() {
        watcher = DirectoryWatcher(directories: [fileURL.deletingLastPathComponent()]) { [weak self] in
            self?.reloadFromDisk()
        }
        // The folder only reports files replaced or renamed; this catches a write into the file.
        fileWatcher = FileWatcher(file: fileURL) { [weak self] in
            self?.reloadFromDisk()
        }
    }

    private func reloadFromDisk() {
        // An atomic save replaced the file, so the old descriptor is gone.
        fileWatcher?.rearm()
        switch Self.read(from: fileURL) {
        case .success(let loaded, let notes):
            self.notes = notes
            loadError = nil
            guard loaded != config else { return }
            lastPersisted = loaded  // don't echo the file back to itself
            config = loaded
        case .failure(let error):
            loadError = error.localizedDescription
        case .missing:
            break  // mid-save or deleted by the user; keep what we have
        }
    }
}
