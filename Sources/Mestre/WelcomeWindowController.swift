import AppKit
import MestreCore
import SwiftUI

/// First-run window, learned by doing: press the hotkey, try the real panel, make it yours.
/// Permissions are not requested here; each feature asks the first time it needs one.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let settings: ConfigStore

    init(settings: ConfigStore, viewModel: SearchViewModel, step: Int = 0, tryQuery: @escaping (String) -> Void, retryHotKeys: @escaping () -> Void, onGetStarted: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WelcomeView.size.width, height: WelcomeView.size.height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Mestre"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let hosting = NSHostingView(rootView: WelcomeView(settings: settings,
                                                          viewModel: viewModel,
                                                          apps: viewModel.apps.index,
                                                          step: WelcomeView.Step(rawValue: step) ?? .shortcut,
                                                          tryQuery: tryQuery,
                                                          retryHotKeys: retryHotKeys,
                                                          getStarted: { [weak self] in self?.finish(then: onGetStarted) },
                                                          openSettings: { [weak self] in self?.finish(then: onOpenSettings) }))
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        // Under the panel, which opens near the top of the screen while this stays up.
        if let visible = window.screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: max(visible.minY, visible.midY - window.frame.height * 0.85)))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func finish(then action: () -> Void) {
        window?.close()
        action()
    }

    /// Seen once: the config remembers, so the next launch goes straight to the menu bar.
    func windowWillClose(_ notification: Notification) {
        settings.config.onboarding.showWelcome = false
    }
}

private struct WelcomeView: View {
    enum Step: Int, CaseIterable { case shortcut, tryIt, makeItYours }

    static let size = CGSize(width: 460, height: 500)

    @ObservedObject var settings: ConfigStore
    let viewModel: SearchViewModel
    /// Still scanning at first launch, when this window opens; the app example follows it.
    @ObservedObject var apps: AppIndex
    @State var step: Step
    let tryQuery: (String) -> Void
    let retryHotKeys: () -> Void
    let getStarted: () -> Void
    let openSettings: () -> Void

    @State private var isChangingShortcut = false
    @State private var tried: Set<String> = []
    /// Nil until read. Read again on coming back from System Settings, the only way it changes here.
    @State private var spotlightHasShortcut: Bool?
    /// What to go back to if ⌘Space turns out not to be wanted.
    @State private var shortcutBeforeSpotlight: KeyCombo?

    @State private var isSwitchingSpotlight = false

    private var usesSpotlightKey: Bool { settings.config.hotKey.isSameKey(as: .spotlight) }

    private func readSpotlight() async {
        let hasShortcut = await Task.detached { SpotlightShortcut.isOn }.value
        // Registering can have failed while Spotlight held the key.
        if spotlightHasShortcut == true, !hasShortcut, usesSpotlightKey { retryHotKeys() }
        spotlightHasShortcut = hasShortcut
    }

    /// Turns Spotlight's shortcut off first, so ⌘Space is free when Mestre registers it. If macOS
    /// doesn't take the change, `spotlightStillOn` explains how to do it by hand.
    private func useSpotlightKey() {
        shortcutBeforeSpotlight = settings.config.hotKey
        isSwitchingSpotlight = true
        Task {
            await Task.detached { SpotlightShortcut.set(on: false) }.value
            settings.config.hotKey = .spotlight
            await readSpotlight()
            isSwitchingSpotlight = false
        }
    }

    private func giveKeyBackToSpotlight() {
        settings.config.hotKey = shortcutBeforeSpotlight ?? .default
        isSwitchingSpotlight = true
        Task {
            await Task.detached { SpotlightShortcut.set(on: true) }.value
            await readSpotlight()
            isSwitchingSpotlight = false
        }
    }

    private func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .shortcut: shortcutStep
                case .tryIt: tryItStep
                case .makeItYours: makeItYoursStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 44)
        .padding(.bottom, 20)
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(.easeOut(duration: 0.15), value: step)
        // Otherwise the first control wears a focus ring as soon as a step opens.
        .focusEffectDisabled()
        // The panel bumps this each time it opens, however the hotkey is spelled.
        .onReceive(viewModel.$focusToken.dropFirst()) { _ in
            if step == .shortcut { step = .tryIt }
        }
        .task { await readSpotlight() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await readSpotlight() }
        }
    }

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.title).bold()
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    // MARK: Step 1

    private var shortcutStep: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
            heading("Welcome to Mestre", "It lives in your menu bar and opens from any app.")
            VStack(spacing: 12) {
                Text("Press").foregroundStyle(.secondary)
                Text(settings.config.hotKey.displayString)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            if let error = settings.hotKeyError {
                ErrorCaption(error).multilineTextAlignment(.center)
            }
            if usesSpotlightKey, spotlightHasShortcut == true {
                spotlightStillOn
            } else if isChangingShortcut || settings.hotKeyError != nil {
                HotKeyRecorder(combo: $settings.config.hotKey, isRecording: $settings.isRecordingHotKey)
                    .sized(width: 170, height: 26)
            } else {
                VStack(spacing: 8) {
                    if usesSpotlightKey {
                        Caption("Spotlight's \(KeyCombo.spotlight.displayString) is now off, so Mestre has it.")
                        Button("Give it back to Spotlight", action: giveKeyBackToSpotlight)
                            .disabled(isSwitchingSpotlight)
                    } else {
                        Button("Use \(KeyCombo.spotlight.displayString) instead of Spotlight", action: useSpotlightKey)
                            .disabled(isSwitchingSpotlight)
                        Caption("This turns off Spotlight's own shortcut. You can give it back here at any time.")
                    }
                    Button("Use a different shortcut") { isChangingShortcut = true }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
        }
    }

    /// macOS gives Spotlight the key first, and only you can turn that off.
    private var spotlightStillOn: some View {
        let back = shortcutBeforeSpotlight ?? .default
        return VStack(spacing: 8) {
            Text("macOS didn't let Mestre turn off Spotlight's \(KeyCombo.spotlight.displayString). In System Settings, open Keyboard Shortcuts › Spotlight and turn it off, then come back and press it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Open Keyboard Settings", action: openKeyboardSettings)
                Button("Go back to \(back.displayString)") { settings.config.hotKey = back }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
    }

    // MARK: Step 2

    /// Follows the config: a renamed keyword shows up renamed, a feature that's off doesn't show.
    private var examples: [(query: String, what: String)] {
        let config = settings.config
        // Safari sits outside the default scan; a short name reads best as something to type.
        let app = apps.apps.first { $0.matches(target: "Safari") } ?? apps.apps.min { $0.name.count < $1.name.count }
        var rows: [(String, String)] = []
        if let app { rows.append((app.name.lowercased(), "open an app")) }
        if config[keyPath: SettingsFeature.calculator.isEnabled] { rows.append(("2^10 + 7", "calculate")) }
        if config[keyPath: SettingsFeature.clipboard.isEnabled] { rows.append((config.clipboard.keyword, "clipboard history")) }
        if config[keyPath: SettingsFeature.windows.isEnabled] { rows.append(("left half", "lay out the front window")) }
        return rows
    }

    /// The keys the panel answers to, as the config has them.
    private var keys: [(cap: String, what: String)] {
        let wanted: [(PanelAction, String)] = [(.open, "run"), (.actions, "actions"), (.complete, "scope"), (.close, "close")]
        return wanted.compactMap { action, what in viewModel.bindings.hint(for: action).map { ($0, what) } }
    }

    private var tryItStep: some View {
        VStack(spacing: 20) {
            heading("Try a few", "Each one opens the real panel. Or type your own.")
            VStack(spacing: 6) {
                ForEach(examples, id: \.query) { example in
                    Button {
                        tried.insert(example.query)
                        tryQuery(example.query)
                    } label: {
                        HStack {
                            Text(example.query).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(example.what).foregroundStyle(.secondary)
                            Image(systemName: tried.contains(example.query) ? "checkmark.circle.fill" : "arrow.up.forward")
                                .foregroundStyle(tried.contains(example.query) ? Color.accentColor : Color.secondary)
                                .frame(width: 18)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 14) {
                ForEach(keys, id: \.cap) { key in
                    HStack(spacing: 5) {
                        KeyHint(key.cap)
                        Text(key.what).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Caption("Window layouts and pasting ask for permission the first time you use them.")
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Step 3

    private var makeItYoursStep: some View {
        VStack(spacing: 16) {
            heading("Make it yours", "Pick a look. You can change it any time.")
            ScrollView {
                ThemePicker(selection: $settings.config.panel.theme, folder: ThemeLibrary.userDirectory(configFile: settings.fileURL),
                            appearance: settings.config.panel.appearance, revision: settings.themeFilesRevision)
                    .padding(4)
            }
            .frame(height: 196)
            Button("See it in the panel") { tryQuery("") }
                .buttonStyle(.link)
                .font(.callout)
            LaunchAtLoginToggle(settings: settings)
                .toggleStyle(.switch)
            Caption("Everything you choose is saved in \(settings.displayPath).")
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            switch step {
            case .shortcut:
                Spacer()
                Button("Skip") { step = .tryIt }
            case .tryIt:
                Button("Back") { step = .shortcut }
                Spacer()
                Button("Continue") { step = .makeItYours }.keyboardShortcut(.defaultAction)
            case .makeItYours:
                Button("Back") { step = .tryIt }
                Button("Settings…", action: openSettings)
                Spacer()
                Button("Get Started", action: getStarted).keyboardShortcut(.defaultAction)
            }
        }
        .overlay {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { dot in
                    Circle()
                        .fill(dot == step ? Color.primary.opacity(0.6) : Color.primary.opacity(0.15))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
        }
    }
}
