# Development

## Build and run

```bash
make run        # builds a release .app into build/ and opens it
make install    # copies build/Mestre.app to ~/Applications and opens it
make test       # unit tests for the matcher and ranker
make build      # plain debug `swift build`
make test-release   # tests for the release scripts
make release    # tags a version and starts the release, see releasing.md
```

`swift run` also works for quick iteration, but launch-at-login needs the real
`.app` bundle, so use `make run` or `make install` to test that.

## Layout

```
Sources/MestreCore   matching, ranking, indexing, key combos, config model — no UI, unit tested
Sources/Mestre       AppKit shell: hotkey, panel, menu bar, settings, SwiftUI views
Tests/MestreCoreTests
Resources/Info.plist   bundle metadata (LSUIElement = menu-bar app)
scripts/bundle.sh      SwiftPM build → .app bundle with Sparkle, ad-hoc or Developer ID signed
scripts/test.sh        swift test with the CLT's Swift Testing paths
scripts/release.sh     tags master; see docs/releasing.md for the rest of the release scripts
```

## Performance

Targets: panel visible in under 50 ms, results in under 5 ms per keystroke for 1 000 apps,
index rebuild under 1 s, 0 % CPU idle. Set `debug.logTimings` to `true` and watch:

```bash
log stream --predicate 'subsystem == "app.mestre" AND category == "perf"' --level info
```

To time the hot path without touching the keyboard, launch with the panel open and a query:

```bash
open build/Mestre.app --args --show --query safari
```

Measured on an Apple Silicon Mac, release build (2026-10): panel show 12–23 ms (cold, at
launch), search 0.2–0.6 ms per keystroke with every provider on, index scan 21 ms for
25 apps, ranking 1 000 long-named apps 4.9 ms per query (`make test`'s PerformanceTests prints
it), 0.0 % CPU idle. The idle figure comes from `top`: Mestre polls nothing but the clipboard
change counter (`clipboard.pollIntervalSeconds`), which is a single integer read.

Sparkle, measured the same way (2026-10, five launches each): panel show 36 ms without it, 36 ms linked
with no update key, 37 ms running with checks off. Search is unchanged and idle CPU stays at 0 %.
