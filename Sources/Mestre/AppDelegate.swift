import AppKit
import Combine
import MestreCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = ConfigStore()
    private let viewModel = SearchViewModel()
    private let textExpander = TextExpander()
    private var panelController: SearchPanelController!
    private var settingsWindow: SettingsWindowController?
    private var welcomeWindow: WelcomeWindowController?
    private var statusItem: NSStatusItem!
    private var openMenuItem: NSMenuItem!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = SearchPanelController(viewModel: viewModel)
        settings.actionTable = ActionTable(providers: viewModel.providers)
        viewModel.commands.confirm = { command in Self.confirm(command.title) }
        viewModel.windows.onPermissionMissing = { [weak self] in self?.explainAccessibility() }
        textExpander.paster = viewModel.clipboard.paster
        textExpander.isSuspended = { [weak self] in self?.panelController.panel.isVisible ?? false }
        viewModel.commands.onInApp = { [weak self] action in
            switch action {
            case .settings: self?.showSettings()
            case .rebuildIndex: self?.rebuildIndex()
            case .editConfig: self?.editConfig()
            case .showDefaults: ConfigStore.showDefaults()
            case .quit: NSApp.terminate(nil)
            case .lockScreen: break  // handled by the provider
            case .toggleKeepAwake: self?.viewModel.keepAwake.manager.toggle()
            }
        }
        setUpStatusItem()
        bindSettings()
        // Not on a broken config: that run uses defaults, so the flag is not the user's.
        if settings.config.onboarding.showWelcome && settings.loadError == nil { showWelcome() }
        applyLaunchArguments()
    }

    /// Developer aids for working on the panel without a keyboard:
    /// `open build/Mestre.app --args --show --query safari --screenshot /tmp/panel.png` shows
    /// the panel, types a query and, a moment later, writes the panel's content to a PNG.
    private func applyLaunchArguments() {
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments[safe: $0 + 1] }
        }
        // `--welcome-screenshot /tmp/welcome.png` writes the welcome window the same way.
        if let path = value(after: "--welcome-screenshot") {
            showWelcome()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.welcomeWindow?.window.map { SearchPanelController.writeScreenshot(of: $0, to: URL(fileURLWithPath: path)) }
            }
        }
        guard arguments.contains("--show") else { return }
        panelController.show()
        if let query = value(after: "--query") { viewModel.query = query }
        if let feature = value(after: "--feature") { openFeature(feature) }
        if let path = value(after: "--screenshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.panelController.writeScreenshot(to: URL(fileURLWithPath: path))
            }
        }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(session: nil, showCup: true)

        let menu = NSMenu()
        openMenuItem = menu.addItem(withTitle: "Open Mestre", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: "Rebuild App Index", action: #selector(rebuildIndex), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Edit Config File", action: #selector(editConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Welcome Guide", action: #selector(showWelcome), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Mestre", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func togglePanel() { panelController.toggle() }

    /// A cup while the Mac is being kept awake (unless `keepAwake.menuBarIcon` is off).
    private func updateStatusIcon(session: KeepAwakeSession?, showCup: Bool) {
        guard let button = statusItem?.button else { return }
        let awake = session != nil && showCup
        button.image = NSImage(systemSymbolName: awake ? "cup.and.saucer.fill" : "sparkle.magnifyingglass", accessibilityDescription: "Mestre")
            ?? NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Mestre")
        button.toolTip = session.map { "Mestre: " + $0.summary().lowercased() } ?? "Mestre"
    }

    @objc private func rebuildIndex() { viewModel.apps.index.rescan() }

    @objc private func editConfig() { settings.openInEditor() }

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings, viewModel: viewModel, expander: textExpander)
        }
        settingsWindow?.show()
    }

    @objc private func showWelcome() {
        if welcomeWindow == nil {
            welcomeWindow = WelcomeWindowController(
                settings: settings,
                onGetStarted: { [weak self] in self?.panelController.show() },
                onOpenSettings: { [weak self] in self?.showSettings() })
        }
        welcomeWindow?.show()
    }

    // MARK: Confirmation

    /// Modal yes/no for destructive commands. Mestre is an accessory app, so it has to
    /// activate to show the alert and hand focus back afterwards.
    private static func confirm(_ title: String) -> Bool {
        let previous = NSWorkspace.shared.frontmostApplication
        let alert = NSAlert()
        alert.messageText = "\(title)?"
        alert.informativeText = "Turn this off in Settings › Commands › Confirm destructive commands."
        alert.addButton(withTitle: title)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if !confirmed { previous?.activate() }
        return confirmed
    }

    private var explainedAccessibility = false

    /// Once per launch: the system prompt plus a pointer to the right pane. Focus goes
    /// back to the app the user was in.
    private func explainAccessibility() {
        guard !explainedAccessibility else { NSSound.beep(); return }
        explainedAccessibility = true
        WindowManager.ensurePermission()
        let previous = NSWorkspace.shared.frontmostApplication
        let alert = NSAlert()
        alert.messageText = "Mestre needs Accessibility access to move windows"
        alert.informativeText = "Allow Mestre under System Settings › Privacy & Security › Accessibility, then press the shortcut again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            WindowManager.openAccessibilitySettings()
        } else {
            previous?.activate()
        }
    }

    // MARK: Hotkey

    private func bindSettings() {
        settings.$hotkeyTable
            .combineLatest(settings.$config.map(\.hotKey).removeDuplicates())
            .dropFirst()
            // @Published emits before the value is set; hop once so registerHotKeys reads the new table.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.registerHotKeys() }
            .store(in: &cancellables)

        settings.$keyBindings
            .removeDuplicates()
            .sink { [weak self] bindings in self?.viewModel.bindings = bindings }
            .store(in: &cancellables)

        settings.$config
            .map(\.panel)
            .removeDuplicates()
            .sink { [weak self] panel in self?.viewModel.layout = panel }
            .store(in: &cancellables)

        settings.$config
            .map(\.home)
            .removeDuplicates()
            .sink { [weak self] home in self?.viewModel.home = home }
            .store(in: &cancellables)

        settings.$config
            .map(\.aliases)
            .removeDuplicates()
            .sink { [weak self] aliases in self?.viewModel.apps.aliases = aliases }
            .store(in: &cancellables)

        settings.$config
            .map(\.commands)
            .removeDuplicates()
            .sink { [weak self] commands in self?.viewModel.commands.settings = commands }
            .store(in: &cancellables)

        settings.$config
            .map(\.scripts)
            .removeDuplicates()
            .sink { [weak self] scripts in self?.viewModel.scripts.settings = scripts }
            .store(in: &cancellables)

        settings.$config
            .map(\.quickKeys)
            .removeDuplicates()
            .sink { [weak self] quickKeys in self?.viewModel.quickKeys = quickKeys }
            .store(in: &cancellables)

        settings.$config
            .map(\.settingsPanes)
            .removeDuplicates()
            .sink { [weak self] panes in self?.viewModel.settingsPanes.settings = panes }
            .store(in: &cancellables)

        settings.$config
            .map(\.processes)
            .removeDuplicates()
            .sink { [weak self] processes in self?.viewModel.processes.settings = processes }
            .store(in: &cancellables)

        settings.$config
            .map(\.keepAwake)
            .removeDuplicates()
            .sink { [weak self] keepAwake in self?.viewModel.keepAwake.settings = keepAwake }
            .store(in: &cancellables)

        // The icon is a function of two inputs; one sink gets both, whatever order they change in.
        viewModel.keepAwake.manager.$session.removeDuplicates()
            .combineLatest(settings.$config.map(\.keepAwake.menuBarIcon).removeDuplicates())
            .sink { [weak self] session, showCup in self?.updateStatusIcon(session: session, showCup: showCup) }
            .store(in: &cancellables)

        settings.$config
            .map(\.quicklinks)
            .removeDuplicates()
            .sink { [weak self] links in self?.viewModel.quicklinks.links = links }
            .store(in: &cancellables)

        settings.$config
            .map(\.windows)
            .removeDuplicates()
            .sink { [weak self] windows in
                self?.viewModel.windows.settings = windows
                self?.viewModel.openWindows.settings = windows
            }
            .store(in: &cancellables)

        settings.$config
            .map(\.clipboard)
            .removeDuplicates()
            .sink { [weak self] clipboard in self?.viewModel.clipboard.settings = clipboard }
            .store(in: &cancellables)

        settings.$config
            .map(\.emoji)
            .removeDuplicates()
            .sink { [weak self] emoji in self?.viewModel.emoji.settings = emoji }
            .store(in: &cancellables)

        settings.$config
            .map(\.files)
            .removeDuplicates()
            .sink { [weak self] files in self?.viewModel.files.settings = files }
            .store(in: &cancellables)

        settings.$config
            .map(\.paths)
            .removeDuplicates()
            .sink { [weak self] paths in self?.viewModel.paths.settings = paths }
            .store(in: &cancellables)

        settings.$config
            .map(\.dictionary)
            .removeDuplicates()
            .sink { [weak self] dictionary in self?.viewModel.dictionary.settings = dictionary }
            .store(in: &cancellables)

        settings.$config
            .map(\.bookmarks)
            .removeDuplicates()
            .sink { [weak self] bookmarks in self?.viewModel.bookmarks.settings = bookmarks }
            .store(in: &cancellables)

        settings.$config
            .map(\.colors)
            .removeDuplicates()
            .sink { [weak self] colors in self?.viewModel.colors.settings = colors }
            .store(in: &cancellables)

        settings.$config
            .map(\.paste)
            .removeDuplicates()
            .sink { [weak self] paste in self?.viewModel.clipboard.paster.settings = paste }
            .store(in: &cancellables)

        settings.$config
            .map(\.snippets)
            .removeDuplicates()
            .sink { [weak self] snippets in
                self?.viewModel.snippets.settings = snippets
                self?.textExpander.config = snippets
            }
            .store(in: &cancellables)

        settings.$config
            .map(\.webSearch)
            .removeDuplicates()
            .sink { [weak self] web in self?.viewModel.web.settings = web }
            .store(in: &cancellables)

        settings.$config
            .map(\.shortcuts)
            .removeDuplicates()
            .sink { [weak self] shortcuts in self?.viewModel.shortcuts.settings = shortcuts }
            .store(in: &cancellables)

        settings.$config
            .map(\.calculator)
            .removeDuplicates()
            .sink { [weak self] calculator in self?.viewModel.calculator.settings = calculator }
            .store(in: &cancellables)

        settings.$config
            .map(\.ranking)
            .removeDuplicates()
            .sink { [weak self] ranking in
                self?.viewModel.apps.ranking = ranking
                self?.viewModel.ranking = ranking
            }
            .store(in: &cancellables)

        settings.$config
            .map(\.debug.logTimings)
            .removeDuplicates()
            .sink { Perf.enabled = $0 }
            .store(in: &cancellables)

        settings.$config
            .map(\.search.maxResults)
            .removeDuplicates()
            .sink { [weak self] maxResults in self?.viewModel.maxResults = maxResults }
            .store(in: &cancellables)

        // Covers first launch and every later change to the scanned folders.
        settings.$config
            .map { AppIndex.Scope(directories: $0.resolvedAppDirectories, depth: $0.search.scanDepth,
                                  watchFolders: $0.search.watchFolders, refreshInterval: $0.search.refreshIntervalSeconds) }
            .removeDuplicates()
            .sink { [weak self] scope in self?.viewModel.apps.index.apply(scope) }
            .store(in: &cancellables)

        // While the user is recording a new shortcut, the old one must not fire.
        settings.$isRecordingHotKey
            .sink { [weak self] recording in
                guard let self else { return }
                if recording {
                    HotKeyManager.shared.unregisterAll()
                } else {
                    self.registerHotKeys()
                }
            }
            .store(in: &cancellables)
    }

    /// What each Carbon hotkey id does. Index 0 is always the panel toggle.
    /// A `feature:<id>` hotkey: opens the panel on that feature; pressed again, closes it.
    private func openFeature(_ id: String) {
        guard let feature = viewModel.feature(id: id) else {
            NSSound.beep()
            NSLog("Hotkey target feature:%@: unknown or disabled", id)
            return
        }
        let controller = panelController!
        if controller.panel.isVisible, viewModel.isShowing(feature) {
            controller.hide()
            return
        }
        if !controller.panel.isVisible { controller.show() }
        viewModel.complete(with: feature.completion)
        viewModel.requestFocus()
    }

    private enum HotkeyTarget { case panel, app(String), window(WindowLayout), feature(String) }

    /// Registers the panel hotkey plus every per-app hotkey in one deterministic pass.
    private func registerHotKeys() {
        guard !settings.isRecordingHotKey else { return }  // the recorder re-arms them when done
        let config = settings.config
        let table = settings.hotkeyTable
        var bindings: [HotkeyTarget] = [.panel]
        var combos: [UInt32: KeyCombo] = [0: config.hotKey]
        for entry in table.entries {
            combos[UInt32(bindings.count)] = entry.combo
            if let layout = HotkeyTable.windowLayout(in: entry.target) {
                bindings.append(.window(layout))
            } else if let feature = HotkeyTable.featureID(in: entry.target) {
                bindings.append(.feature(feature))
            } else {
                bindings.append(.app(entry.target))
            }
        }

        HotKeyManager.shared.onPress = { [weak self] id in
            guard let self, let binding = bindings[safe: Int(id)] else { return }
            switch binding {
            case .panel:
                self.panelController.toggle()
            case .window(let layout):
                self.viewModel.windows.apply(layout)
            case .feature(let id):
                self.openFeature(id)
            case .app(let target):
                // A hotkey target is an app name or bundle id first, else a command id or title.
                do {
                    try self.viewModel.apps.open(matching: target)
                } catch AppProvider.OpenError.notInstalled where self.viewModel.commands.run(matching: target) {
                    return
                } catch {
                    NSSound.beep()
                    NSLog("Hotkey target %@: %@", target, String(describing: error))
                }
            }
        }

        let failures = HotKeyManager.shared.replaceAll(with: combos)
        settings.hotKeyError = failures[0].map { "Couldn't register \(config.hotKey.displayString): \($0.localizedDescription)" }
        var errors: [String: String] = [:]
        for text in table.invalid { errors[text] = "unrecognised shortcut" }
        for text in table.duplicates { errors[text] = "same key as another hotkey" }
        for (index, entry) in table.entries.enumerated() {
            if let error = failures[UInt32(index + 1)] { errors[entry.text] = error.localizedDescription }
        }
        settings.hotkeyErrors = errors
        for (text, reason) in errors { NSLog("Hotkey %@: %@", text, reason) }
        NSLog("Hotkeys registered: %d of %d", combos.count - failures.count, combos.count)
        openMenuItem.title = "Open Mestre\t\(config.hotKey.displayString)"
    }
}
