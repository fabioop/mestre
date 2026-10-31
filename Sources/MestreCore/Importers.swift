import AppKit
import Foundation

/// What an import found, ready to merge into the config. Entries whose name or key already
/// exists in the config are skipped by `Config.merge`.
public struct ImportResult: Equatable, Sendable {
    public var snippets: [Snippet] = []
    public var quicklinks: [Quicklink] = []
    /// Shortcut config string → app name.
    public var hotkeys: [String: String] = [:]
    /// Things that were recognised but couldn't be converted, for the user to see.
    public var warnings: [String] = []

    public init() {}

    public var isEmpty: Bool { snippets.isEmpty && quicklinks.isEmpty && hotkeys.isEmpty }

    /// Appends another import's findings; the first hotkey for a combo wins.
    public mutating func formUnion(_ other: ImportResult) {
        snippets += other.snippets
        quicklinks += other.quicklinks
        hotkeys.merge(other.hotkeys) { mine, _ in mine }
        warnings += other.warnings
    }
}

/// How many of each kind an import added.
public struct ImportSummary: Equatable, Sendable {
    public var snippets = 0, quicklinks = 0, hotkeys = 0
}

public extension Config {
    /// Adds imported entries whose name or shortcut isn't taken, by the config or by an earlier
    /// entry of the same import (snippets and quicklinks are identified by name).
    @discardableResult
    mutating func merge(_ imported: ImportResult) -> ImportSummary {
        var summary = ImportSummary()
        summary.snippets = Self.appendNew(imported.snippets, to: &snippets.items, name: \.name)
        summary.quicklinks = Self.appendNew(imported.quicklinks, to: &quicklinks, name: \.name)
        // Compare parsed combos, not spellings: "alt+t" in the file already owns "option+t".
        var taken = Set((Array(hotkeys.keys) + Array(hotkeyDefaults.keys)).compactMap { KeyCombo(parsing: $0) })
        taken.insert(hotKey)
        for (text, target) in imported.hotkeys.sorted(by: { $0.key < $1.key }) {
            guard let combo = KeyCombo(parsing: text), taken.insert(combo).inserted else { continue }
            hotkeys[text] = target
            summary.hotkeys += 1
        }
        return summary
    }

    private static func appendNew<T>(_ new: [T], to list: inout [T], name: (T) -> String) -> Int {
        var seen = Set(list.map { name($0).lowercased() })
        let fresh = new.filter { seen.insert(name($0).lowercased()).inserted }
        list += fresh
        return fresh.count
    }
}

// MARK: - Raycast

/// Raycast keeps its data encrypted, so this reads the JSON files its "Export Snippets" and
/// "Export Quicklinks" commands write (the same shape its import commands accept).
/// Hotkeys only leave Raycast inside the encrypted .rayconfig and can't be imported.
public enum RaycastImport {
    public enum Failure: Error, Equatable { case notRaycastJSON }

    /// Accepts either export: a snippets array (`name`, `text`, `keyword`) or a quicklinks
    /// array (`name`, `link`, `openWith`).
    public static func parse(_ data: Data) throws -> ImportResult {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw Failure.notRaycastJSON
        }
        var result = ImportResult()
        for object in array {
            guard let name = object["name"] as? String, !name.isEmpty else { continue }
            if let text = object["text"] as? String {
                result.snippets.append(Snippet(name: name, text: convertPlaceholders(text), keyword: object["keyword"] as? String))
                for placeholder in unsupportedPlaceholders(in: text) {
                    result.warnings.append("\(name): \(placeholder) is kept as plain text, Mestre has no equivalent")
                }
            } else if let link = object["link"] as? String {
                if let app = object["openWith"] as? String, !app.isEmpty {
                    result.warnings.append("\(name): opens with \(app) in Raycast; Mestre opens it in the default app")
                }
                result.quicklinks.append(Quicklink(name: name, url: convertQuery(link)))
            }
        }
        if result.isEmpty && !array.isEmpty { throw Failure.notRaycastJSON }
        return result
    }

    /// `{argument}`, `{argument name="x"}` and `{Query}` all mean the typed text.
    static func convertQuery(_ link: String) -> String {
        link.replacingOccurrences(of: #"\{(?:argument(?:\s+[^}]*)?|query)\}"#, with: Quicklink.placeholder,
                                  options: [.regularExpression, .caseInsensitive])
    }

    /// Raycast's dynamic placeholders share Mestre's names, except that a custom format is
    /// written `{date format="…"}` (also on time/datetime) and Mestre spells it `{date:…}`.
    static func convertPlaceholders(_ text: String) -> String {
        text.replacingOccurrences(of: #"\{(?:date|time|datetime)\s+format="([^"]*)"\s*\}"#, with: "{date:$1}", options: .regularExpression)
    }

    /// Placeholders Mestre has no equivalent for (offsets, arguments), reported as warnings.
    static func unsupportedPlaceholders(in text: String) -> [String] {
        let pattern = #"\{(?:date|time|datetime)\s+[^}]*offset[^}]*\}|\{argument[^}]*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
}

// MARK: - Alfred

/// Reads Alfred's preferences folder: custom web searches (quicklinks), snippet collections
/// and workflow hotkeys that launch an app.
public enum AlfredImport {
    /// Where Alfred keeps preferences unless a sync folder is set.
    public static let defaultDirectory = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Alfred/Alfred.alfredpreferences")

    public static func read(directory: URL, fileManager: FileManager = .default) throws -> ImportResult {
        var result = ImportResult()
        let websearch = directory.appendingPathComponent("preferences/features/websearch/prefs.plist")
        if let data = try? Data(contentsOf: websearch) {
            do {
                result.quicklinks = try customSearches(from: data)
            } catch {
                result.warnings.append("Web searches skipped, prefs.plist is unreadable: \(error.localizedDescription)")
            }
        }
        let snippetsDir = directory.appendingPathComponent("snippets")
        if let files = fileManager.enumerator(at: snippetsDir, includingPropertiesForKeys: nil) {
            for case let url as URL in files where url.pathExtension == "json" {
                if let data = try? Data(contentsOf: url), let snippet = try? snippet(from: data) {
                    result.snippets.append(snippet)
                }
            }
        }
        let workflowsDir = directory.appendingPathComponent("workflows")
        if let folders = try? fileManager.contentsOfDirectory(at: workflowsDir, includingPropertiesForKeys: nil) {
            for folder in folders {
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("info.plist")),
                      let found = try? workflowHotkeys(from: data) else { continue }
                result.formUnion(found)
            }
        }
        result.snippets.sort { $0.name < $1.name }
        return result
    }

    /// `preferences/features/websearch/prefs.plist`: `customSites` → `{text, url, keyword, enabled}`.
    public static func customSearches(from data: Data) throws -> [Quicklink] {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let sites = plist["customSites"] as? [String: [String: Any]] else { return [] }
        return sites.values.compactMap { site in
            guard site["enabled"] as? Bool ?? true,
                  let name = site["text"] as? String, !name.isEmpty,
                  let url = site["url"] as? String, !url.isEmpty else { return nil }
            return Quicklink(name: name, url: url, keyword: site["keyword"] as? String)
        }
        .sorted { $0.name < $1.name }
    }

    /// `snippets/<collection>/<uid>.json`: `{"alfredsnippet": {"name", "snippet", "keyword"}}`.
    public static func snippet(from data: Data) throws -> Snippet? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = object["alfredsnippet"] as? [String: Any],
              let name = inner["name"] as? String, !name.isEmpty,
              let text = inner["snippet"] as? String else { return nil }
        return Snippet(name: name, text: convertPlaceholders(text), keyword: inner["keyword"] as? String)
    }

    /// `{clipboard}`, `{cursor}` and `{date:<pattern>}` already match Mestre's. Alfred's named
    /// styles (`{date:short}`, `{time:long}`) become the plain placeholder; `{random:uuid}` is
    /// `{uuid}`. Offsets such as `{date +1d}` stay as typed.
    static func convertPlaceholders(_ text: String) -> String {
        text.replacingOccurrences(of: "{random:uuid}", with: "{uuid}", options: .caseInsensitive)
            .replacingOccurrences(of: #"\{(date|time|datetime):(?:short|medium|long|full)\}"#, with: "{$1}", options: [.regularExpression, .caseInsensitive])
    }

    /// A workflow's `info.plist`: hotkey triggers wired to a "Launch Apps/Files" action become
    /// hotkey → app name entries. Anything else a hotkey triggers is out of scope, and so is
    /// a disabled workflow.
    public static func workflowHotkeys(from data: Data) throws -> ImportResult {
        var result = ImportResult()
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["disabled"] as? Bool != true,
              let objects = plist["objects"] as? [[String: Any]] else { return result }
        let workflow = plist["name"] as? String ?? "workflow"
        let connections = plist["connections"] as? [String: [[String: Any]]] ?? [:]
        var launchers: [String: String] = [:]  // uid → app path
        for object in objects where object["type"] as? String == "alfred.workflow.action.launchfiles" {
            guard let uid = object["uid"] as? String,
                  let paths = (object["config"] as? [String: Any])?["paths"] as? [String],
                  let app = paths.first(where: { $0.hasSuffix(".app") }) else { continue }
            launchers[uid] = app
        }
        for object in objects where object["type"] as? String == "alfred.workflow.trigger.hotkey" {
            guard let uid = object["uid"] as? String,
                  let config = object["config"] as? [String: Any],
                  let keyCode = config["hotkey"] as? Int,
                  let modifiers = config["hotmod"] as? UInt,
                  let app = connections[uid]?.compactMap({ $0["destinationuid"] as? String }).compactMap({ launchers[$0] }).first
            else { continue }
            // Mestre's hotkey targets are app names or bundle ids, not paths.
            let appName = URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
            let label = KeyCombo.label(forKeyCode: UInt16(keyCode), characters: config["hotstring"] as? String)
            let combo = KeyCombo(keyCode: UInt32(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: modifiers), keyLabel: label)
            guard !combo.modifiers.isEmpty else { continue }  // modifier-only or unset triggers aren't global hotkeys
            let text = combo.configString
            guard combo.readsBack() else {
                result.warnings.append("\(workflow): the hotkey for \(appName) (\(combo.displayString)) has no spelling Mestre can read; add it under Shortcuts")
                continue
            }
            if result.hotkeys[text] == nil { result.hotkeys[text] = appName }
        }
        return result
    }
}
