import AppKit
import MestreCore
import SwiftUI

/// Brings snippets, quicklinks and app hotkeys over from Raycast or Alfred, merging into
/// the config without touching entries that already exist.
struct ImportPage: View {
    @ObservedObject var settings: ConfigStore
    @State private var report: String?
    @State private var warnings: [String] = []

    var body: some View {
        Section("Import") {
            HStack {
                Button("From Raycast…") { importRaycast() }
                Button("From Alfred…") { importAlfred() }
            }
            Caption("Raycast: run its Export Snippets and Export Quicklinks commands first, then pick the JSON files. Its hotkeys can't be exported, so add them under Shortcuts.")
            Caption("Alfred: brings over web searches, snippets and hotkeys that launch an app.")
        }
        if let report {
            Section("Result") {
                Text(report)
                ForEach(warnings, id: \.self) { Caption($0) }
            }
        }
    }

    private func importRaycast() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.message = "Choose the JSON files Raycast exported"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task.detached {
            var combined = ImportResult()
            for url in urls {
                do {
                    combined.formUnion(try RaycastImport.parse(try Data(contentsOf: url)))
                } catch {
                    combined.warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            await apply(combined)
        }
    }

    private func importAlfred() {
        var directory = AlfredImport.defaultDirectory
        if !FileManager.default.fileExists(atPath: directory.path) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.message = "Choose the Alfred.alfredpreferences folder"
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            directory = chosen
        }
        let chosen = directory
        Task.detached {
            do {
                await apply(try AlfredImport.read(directory: chosen))
            } catch {
                await show("Couldn't read \(chosen.lastPathComponent): \(error.localizedDescription)", warnings: [])
            }
        }
    }

    /// Reading happens off the main thread; merging into the config is main-actor work.
    @MainActor private func apply(_ result: ImportResult) {
        let added = settings.config.merge(result)
        show("Added \(added.snippets) of \(result.snippets.count) snippets, \(added.quicklinks) of \(result.quicklinks.count) quicklinks, \(added.hotkeys) of \(result.hotkeys.count) hotkeys. Entries whose name or shortcut already existed were left alone.",
             warnings: result.warnings)
    }

    @MainActor private func show(_ report: String, warnings: [String]) {
        self.report = report
        self.warnings = warnings
    }
}
