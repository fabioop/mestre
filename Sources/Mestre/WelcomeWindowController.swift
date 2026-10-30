import AppKit
import MestreCore
import SwiftUI

/// First-run window: explains the hotkey and what to type. Permissions are not requested
/// here; each feature asks the first time it needs one.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let settings: ConfigStore

    init(settings: ConfigStore, onGetStarted: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
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
                                                          getStarted: { [weak self] in self?.finish(then: onGetStarted) },
                                                          openSettings: { [weak self] in self?.finish(then: onOpenSettings) }))
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
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
    @ObservedObject var settings: ConfigStore
    let getStarted: () -> Void
    let openSettings: () -> Void

    /// Keyword-driven rows follow the config, so a renamed keyword shows up renamed.
    private var examples: [(String, String)] {
        let config = settings.config
        return [
            ("safari", "open an app"),
            ("2^10 + 7", "calculate"),
            ("left half", "lay out the front window"),
            (config.clipboard.keyword, "clipboard history"),
            ("\(config.dictionary.keyword) serendipity", "look up a word"),
            ("#ff8800", "convert a colour"),
        ]
    }

    /// The keys that are not obvious from typing, with the caps the panel itself uses.
    private let keys: [(cap: String, what: String)] = [
        ("⇥", "scope a feature or search, or unfold a row's actions; ⌫ on an empty field leaves"),
        ("sl", "two-letter quick keys on commands and features: type one to bring up its row"),
    ]

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 6) {
                Text("Welcome to Mestre").font(.title).bold()
                Text("A launcher that lives in your menu bar.").foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text(settings.config.hotKey.displayString)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                Text("opens Mestre from any app. Esc closes it.")
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(examples, id: \.0) { example, what in
                    GridRow {
                        Text(example).font(.system(.body, design: .monospaced))
                        Text(what).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(keys, id: \.cap) { cap, what in
                    GridRow {
                        KeyHint(cap).gridColumnAlignment(.trailing)
                        Text(what).foregroundStyle(.secondary).font(.callout)
                    }
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            Text("Window layouts, pasting and text expansion ask for Accessibility or Input Monitoring the first time you use them. Nothing is requested now.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            LaunchAtLoginToggle().toggleStyle(.switch)

            HStack {
                Button("Settings…", action: openSettings)
                Spacer()
                VStack(spacing: 2) {
                    Text("Everything is in ~/.config/mestre/config.json").font(.caption).foregroundStyle(.tertiary)
                    Button("Show every default…") { ConfigStore.showDefaults() }.buttonStyle(.link).font(.caption)
                }
                Spacer()
                Button("Get Started", action: getStarted).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460)
    }
}
