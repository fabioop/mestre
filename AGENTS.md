# Mestre

macOS launcher. Swift, AppKit + SwiftUI, menu-bar app.
Name: Mestre (Portuguese for "master"). Bundle id `app.mestre.Mestre`, config at `~/.config/mestre/config.json`.

## Core principles (non-negotiable)

1. **Blazing fast.** Budgets: panel visible < 50 ms after the hotkey, keystroke → results < 5 ms for 1 000 apps, index rebuild < 1 s, 0 % CPU idle, no disk or network I/O on the main thread, no polling where a notification exists. Measure before and after any change on the hot path (hotkey → show → search → open). A feature that can't meet the budget ships behind a config flag that defaults off, or not at all.
2. **100 % configurable through the config file.** Every user-facing behaviour, shortcut, number and path has a key in `~/.config/mestre/config.json` with a sensible default. The file is the source of truth; the Settings window only edits it. No UserDefaults for settings (usage stats are data, not settings). New feature → new config keys, documented in docs/configuration.md, one line in the README's feature table when it is a new feature, decoded with `decodeIfPresent` so old files keep working.

## Build / test

- No Xcode on this machine, only Command Line Tools: never use `xcodebuild`.
- `make run` — release build + `.app` bundle in `build/`, then opens it. `make install` copies to `~/Applications`.
- `make icon` — redraws `Resources/Mestre.icns` from `scripts/make-icon.swift` (CoreGraphics, no design tools).
- `make test` — runs `scripts/test.sh` (plain `swift test` fails: Swift Testing needs the CLT framework paths).
- Targets: `MestreCore` (pure logic, tested), `Mestre` (app). Swift language mode 5 to keep AppKit interop simple.

## Conventions

- Commits follow Conventional Commits: `type(scope): summary`, for example `fix(panel): keep the glass view attached` or `feat(themes): add the micro theme`.
- Global hotkey uses Carbon `RegisterEventHotKey` (no Accessibility permission needed). Default ⌥Space.
- The search panel is a non-activating `NSPanel`; keyboard navigation goes through the `NSTextField` delegate's `doCommandBy:` (moveUp:/moveDown:/insertNewline:/cancelOperation:), not event monitors.
- All user settings go through `Config` (MestreCore) and `ConfigStore` (app): JSON at `~/.config/mestre/config.json`, every key optional with a default, file watched for live reload. Never add a setting to UserDefaults; usage stats are the one exception (data, not config).
- Default search scope is user-installed apps (/Applications, ~/Applications); system apps are opt-in via `search.includeSystemApps`.
- Prefer AppKit where SwiftUI on macOS is awkward (text field focus, key handling); SwiftUI for layout.
- Shortcut conventions: ⌃⌥ for window management and other global defaults. `hyper` (⌘⌥⌃⇧) is available as a modifier but needs a remapper, so no default uses it.
