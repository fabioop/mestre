import AppKit
import MestreCore

/// "~/Doc" or "/Applications/" browses the file system like a shell completion:
/// folders first, Return steps into a folder or opens a file.
@MainActor
final class PathProvider: ResultProvider {
    nonisolated let id = "paths"
    nonisolated let declaredActions = FileItem.folderActions + FileItem.fileActions

    var settings = Config.Paths()
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)? {
        didSet { lister.onLoaded = onChange }
    }
    var replaceQuery: ((String) -> Void)?

    private let lister = DirectoryLister()

    func owns(_ query: Query) -> Bool { settings.enabled && PathCompletion.isPath(query.text) }

    /// The folder being browsed, with the home directory abbreviated.
    func chips(for query: Query) -> [String] {
        guard let target = PathCompletion.target(for: query.text) else { return [] }
        return [(target.directory as NSString).abbreviatingWithTildeInPath]
    }

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "paths", title: "Browse Folders", subtitle: "Type a path like ~/Documents or /Applications/", symbol: "folder", completion: "~/")
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard owns(query), let target = PathCompletion.target(for: query.text), let entries = lister.entries(of: target.directory) else { return [] }
        let shown = PathCompletion.filter(entries, prefix: target.prefix, showHidden: settings.showHidden, limit: min(limit, settings.maxResults))
        let items = shown.map { entry in
            FileItem(url: URL(fileURLWithPath: (target.directory as NSString).appendingPathComponent(entry.name)),
                     isDirectory: entry.isDirectory,
                     completion: target.typedDirectory + entry.name + (entry.isDirectory ? "/" : ""))
        }
        return ScoredItem.pinned(items, provider: self)
    }

    func queryLeft() { lister.clear() }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let item = item as? FileItem else { return }
        if action.id == "enter", let completion = item.completion { replaceQuery?(completion); return }
        if !FileActions.perform(action, on: item.url, dismiss: dismiss) { NSSound.beep() }
    }
}
