import AppKit
import MestreCore

/// A built-in command: something the launcher can do without an app.
struct Command: SearchItem {
    enum Run {
        /// Runs `osascript -e` off the main thread. macOS asks once for Automation consent.
        case appleScript(String)
        /// Runs an executable off the main thread.
        case process(String, [String])
        /// Something inside Mestre; the provider resolves it.
        case inApp(CommandProvider.InApp)
        /// A public-API system action, or one that reads a setting (volume step, Wi-Fi, apps).
        case system(SystemAction)
    }

    let id: String
    let title: String
    let iconSymbol: String?
    var keywords: [String] = []
    /// Asks for confirmation first when `commands.confirmDestructive` is on.
    var destructive = false
    /// A feature switch in another config section (`ocr.enabled`): off leaves the command out,
    /// like a hidden one.
    var requires: KeyPath<Config, Bool>? = nil
    let run: Run

    var icon: NSImage? { nil }
    var kind: ItemKind { .command }
    var actions: [ItemAction] { Self.actions }

    static let actions = [ItemAction(id: "run", title: "Run", icon: "play")]

    /// True when `target` is this command's id or title, case-insensitively.
    func matches(target: String) -> Bool {
        id.caseInsensitiveCompare(target) == .orderedSame || title.caseInsensitiveCompare(target) == .orderedSame
    }
}

/// System and Mestre commands, ranked like apps by fuzzy match on title and keywords.
@MainActor
final class CommandProvider: ResultProvider {
    nonisolated let declaredActions = Command.actions
    enum InApp { case settings, rebuildIndex, editConfig, showDefaults, quit, lockScreen, toggleKeepAwake, copyTextFromScreen }

    nonisolated let id = "commands"
    var settings = Config.Commands() {
        didSet { updateVisible() }
    }
    /// The `requires` switches that are off in the config.
    private var switchedOff: Set<KeyPath<Config, Bool>> = []
    private static let requirements = Set(all.compactMap(\.requires))

    /// Reads the switches commands declare with `requires`; the list is recomputed only when one flips.
    func apply(_ config: Config) {
        let off = Self.requirements.filter { !config[keyPath: $0] }
        if off != switchedOff {
            switchedOff = off
            updateVisible()
        }
    }

    private func updateVisible() {
        let visibility = Visibility(settings.enabled, hidden: settings.hidden)
        visible = visibility.filter(Self.all.filter { $0.requires.map { !switchedOff.contains($0) } ?? true }) { [$0.id, $0.title] }
        setVolumeShown = settings.enabled && !visibility.hides([Self.setVolumeID])
    }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?
    var onInApp: ((InApp) -> Void)?
    /// Injected by the host so UI (an alert) stays out of the provider. Defaults to "yes".
    var confirm: (Command) -> Bool = { _ in true }

    static let all: [Command] = [
        Command(id: "sleep", title: "Sleep", iconSymbol: "moon.zzz", keywords: ["suspend"], run: .process("/usr/bin/pmset", ["sleepnow"])),
        Command(id: "lockScreen", title: "Lock Screen", iconSymbol: "lock", keywords: ["lock"], run: .inApp(.lockScreen)),
        Command(id: "restart", title: "Restart", iconSymbol: "arrow.clockwise.circle", keywords: ["reboot"], destructive: true,
                run: .appleScript("tell application \"loginwindow\" to «event aevtrrst»")),
        Command(id: "shutDown", title: "Shut Down", iconSymbol: "power.circle", keywords: ["power off", "shutdown"], destructive: true,
                run: .appleScript("tell application \"loginwindow\" to «event aevtrsdn»")),
        Command(id: "logOut", title: "Log Out", iconSymbol: "rectangle.portrait.and.arrow.right", keywords: ["logout", "sign out"], destructive: true,
                run: .appleScript("tell application \"loginwindow\" to «event aevtrlgo»")),
        Command(id: "emptyTrash", title: "Empty Trash", iconSymbol: "trash", keywords: ["bin"], destructive: true,
                run: .appleScript("tell application \"Finder\" to empty trash")),
        Command(id: "toggleDarkMode", title: "Toggle Dark Mode", iconSymbol: "circle.lefthalf.filled", keywords: ["appearance", "light mode", "theme"],
                run: .appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")),
        Command(id: "ejectAll", title: "Eject All Disks", iconSymbol: "eject", keywords: ["unmount", "volumes"], destructive: true,
                run: .appleScript("tell application \"Finder\" to eject (every disk whose ejectable is true)")),
        Command(id: "volumeUp", title: "Volume Up", iconSymbol: "speaker.wave.3", keywords: ["louder", "sound"], run: .system(.volumeUp)),
        Command(id: "volumeDown", title: "Volume Down", iconSymbol: "speaker.wave.1", keywords: ["quieter", "softer", "sound"], run: .system(.volumeDown)),
        Command(id: "toggleMute", title: "Toggle Mute", iconSymbol: "speaker.slash", keywords: ["mute", "unmute", "volume", "sound"], run: .appleScript(VolumeQuery.toggleMuteScript)),
        Command(id: "toggleWiFi", title: "Toggle Wi-Fi", iconSymbol: "wifi", keywords: ["wifi", "wireless", "airport", "network"], run: .system(.toggleWiFi)),
        Command(id: "toggleHiddenFiles", title: "Toggle Hidden Files", iconSymbol: "eye", keywords: ["show hidden", "dotfiles", "finder"],
                run: .process("/bin/sh", ["-c", """
                case "$(/usr/bin/defaults read com.apple.finder AppleShowAllFiles 2>/dev/null)" in 1|YES|yes|TRUE|true) show=false;; *) show=true;; esac
                /usr/bin/defaults write com.apple.finder AppleShowAllFiles -bool $show && /usr/bin/killall Finder
                """])),
        Command(id: "hideOtherApps", title: "Hide Other Apps", iconSymbol: "rectangle.on.rectangle.slash", keywords: ["hide others"], run: .system(.hideOtherApps)),
        Command(id: "quitAllApps", title: "Quit All Apps", iconSymbol: "xmark.square", keywords: ["close all", "quit everything"], destructive: true, run: .system(.quitAllApps)),
        Command(id: "hideAllApps", title: "Hide All Apps", iconSymbol: "macwindow.on.rectangle", keywords: ["hide windows"], run: .system(.hideAllApps)),
        Command(id: "copyTextFromScreen", title: "Copy Text from Screen", iconSymbol: "text.viewfinder",
                keywords: ["ocr", "grab text", "copy text", "screen text", "recognize text", "recognise text"],
                requires: \Config.ocr.enabled, run: .inApp(.copyTextFromScreen)),
        Command(id: "keepAwake", title: "Keep Awake", iconSymbol: "cup.and.saucer", keywords: ["caffeinate", "no sleep", "stay awake"], run: .inApp(.toggleKeepAwake)),
        Command(id: "mestreSettings", title: "Mestre Settings", iconSymbol: "gearshape", keywords: ["preferences", "config"], run: .inApp(.settings)),
        Command(id: "editConfig", title: "Edit Mestre Config File", iconSymbol: "doc.text", keywords: ["json", "settings file"], run: .inApp(.editConfig)),
        Command(id: "showDefaults", title: "Show Default Config", iconSymbol: "doc.text.magnifyingglass", keywords: ["defaults", "documentation", "every key"], run: .inApp(.showDefaults)),
        Command(id: "rebuildIndex", title: "Rebuild App Index", iconSymbol: "arrow.triangle.2.circlepath", keywords: ["rescan", "refresh apps"], run: .inApp(.rebuildIndex)),
        Command(id: "quitMestre", title: "Quit Mestre", iconSymbol: "xmark.circle", run: .inApp(.quit)),
    ]

    /// Commands the config hasn't disabled or hidden; recomputed only when `settings` changes.
    private var visible: [Command] = CommandProvider.all
    /// What the home screen and the quick-key assignment see.
    var visibleCommands: [Command] { visible }

    /// "volume 30" offers a row that sets that level; it is hidden like any command.
    static let setVolumeID = "setVolume"
    private var setVolumeShown = true

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard !query.isEmpty else { return [] }
        let ranked = Ranker.rank(visible, query: query.text, limit: limit, provider: self)
        guard setVolumeShown, limit > 0, let level = VolumeQuery.level(in: query.words) else { return ranked }
        let row = Command(id: Self.setVolumeID, title: "Set Volume to \(level)%", iconSymbol: "speaker.wave.2", run: .appleScript(VolumeQuery.setScript(level: level)))
        return ScoredItem.pinned([row], provider: self) + ranked.prefix(max(0, limit - 1))
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let command = item as? Command else { return }
        run(command)
    }

    /// Every visible command, for the home screen.
    func homeRows() -> [ScoredItem] {
        visible.map { ScoredItem(item: $0, score: 0, provider: self) }
    }

    /// The visible command whose id or title is `target` (hotkey targets).
    func command(matching target: String) -> Command? {
        visible.first { $0.matches(target: target) }
    }

    /// For global hotkeys: runs the visible command whose id or title is `target`.
    func run(matching target: String) -> Bool {
        guard let command = command(matching: target) else { return false }
        run(command)
        return true
    }

    private func run(_ command: Command) {
        dismiss?()
        if command.destructive, settings.confirmDestructive, !confirm(command) { return }
        switch command.run {
        case .inApp(.lockScreen):
            Self.lockScreen()
        case .inApp(let action):
            onInApp?(action)
        case .appleScript(let source):
            ProcessRunner.run("/usr/bin/osascript", ["-e", source], label: command.title)
        case .process(let path, let arguments):
            ProcessRunner.run(path, arguments, label: command.title)
        case .system(let action):
            SystemActions.perform(action, title: command.title, settings: settings)
        }
    }

    /// macOS has no public lock-screen API and CGSession is gone since macOS 26.
    /// SACLockScreenImmediate from the login framework is what the menu bar uses;
    /// if it ever disappears, fall back to sleeping the display (locks when
    /// "require password immediately" is on).
    private static func lockScreen() {
        typealias Lock = @convention(c) () -> Int32
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(symbol, to: Lock.self)()
            return
        }
        ProcessRunner.run("/usr/bin/pmset", ["displaysleepnow"], label: "Lock Screen")
    }
}
