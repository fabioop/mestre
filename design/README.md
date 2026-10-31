Mestre is a keyboard launcher that lives in the macOS menu bar. The system below describes how its one panel, its menus and its two windows look and behave, and the rules behind what is shown and what stays hidden. Values are lifted from the Swift views and `Config.Panel`; a rule marked **Proposed** is not in the code yet.

## Direction

Mestre looks like a 2026 launcher: one dense list, one line per item, a footer that says what Return does, a brand accent, glass. It keeps its own grammar:

- **No modes.** A feature is typed, never entered. The footer names the feature that owns the query instead of a navigation stack, and esc always closes.
- **Kind, not extension.** Every row says what it is (App, File, Command) at the trailing edge, in words. There are no extension icons, badges or chips.
- **Violet.** The accent is the app icon's violet; selection is a tint of it, never a solid fill.
- **Uppercase section labels** with tracking, and a Mestre glyph in the footer, are the two typographic signatures.
- **Nothing moves.** No animation, no selection that follows late results, no actions reordered by use.

## Principles

1. **Speed is the brand.** Nothing in this system may cost the hot path (hotkey → show → search → open). No animation but the system window fade, no shadow but the system one, no image that is not already in memory. If a visual costs a frame, it ships behind a config key that defaults off.
2. **Stable over clever.** The list never reorders under the user's fingers and the actions menu never reorders by usage. Exact and prefix matches beat usage history; history only breaks ties. The selection is where the user left it when Return lands.
3. **One line per item.** The subtitle sits inline after the title in `subtitle` on `ink-secondary`, and truncates first. It is there only when it carries something the title does not: the expression behind a result, a snippet's keyword, a clipboard entry's age, a feature's hint. A path, a folder, "Browser", "Window" and a URL are metadata, shown on the selected row only; an alias that matched is shown after the title on every row, "Firefox (ff)" (`panel.subtitles: selected`, the default; `always` restores every second line). Each `ItemKind` declares which it is; an item may override.
4. **Hints live in the footer.** The bar under the list says what Return and ⌘K do for the selected row, as word plus key cap, and names the feature that owns the query on the left. Rows never carry hints, so their trailing edge never changes on selection. `panel.showFooter: false` removes it.
5. **Everything has a key in config.json.** Every size, colour, position and keyword here is a config key with a default. The Settings window edits the file; it never owns a value.
6. **Native, with one colour of its own.** Colours are macOS semantic colours over a vibrancy material; type is San Francisco; corners are continuous. The one brand decision is the accent: `mestre` (the icon's violet, lifted in dark) by default, `system` or any colour through `panel.accentColor`. `mark-indigo` and `mark-spark` stay on the icon.

## Content

- **Voice.** Short, plain, imperative. "Show in Finder", "Copy Path", "Keep awake for 45 min". Sentence case for titles and actions; no trailing punctuation except the ellipsis on actions that open something else ("Settings…", "Search…").
- **Empty states say what to type.** "No apps match “xqz”" names the query; "Keep awake: 45m, 2h, until 18:30, off" lists the grammar. Never "No results".
- **Keys are glyphs, in the order ⌃⌥⇧⌘**, then the key: ↩ ⇥ esc ⌫ ⌦ ↑ ↓ ← → Space F1–F20. Written inside a `KeyHint` cap, never inline in prose.
- **Kind labels are one word**: App, File, Command, Feature, Calculator, Clipboard, Snippet, Window, Web. They are the `KindBadge`, in `kind` on `ink-secondary`, on every row.
- **No emoji in chrome.** Emoji appear only as the content of the Emoji feature's rows.
- **The config path is written as a path**: `~/.config/mestre/config.json`, in `field-mono`.

## Colour

Mestre paints with system colours so it inherits the user's appearance and accent. Tokens name the role, not the hue.

- The panel ground is the material: `panel` is its opaque equivalent and the fallback for `panel.material = none`. Windows (Settings, Welcome, alerts) use `panel-raised`.
- Text is `ink` for the query, titles and actions; `ink-secondary` for subtitles, hints, section headers and symbols. Both read on `panel` and `panel-raised` at 4.5:1 or better in both themes.
- `ink-tertiary` is reserved for placeholders. It is Apple's tertiary label at about 2.3:1 and fails the text floor: never put anything the user needs to read in it.
- The accent is `accent`: Mestre violet in light, a lifted violet in dark, or whatever `panel.accentColor` resolves to. Selection is `selection` (accent at 16 %, or a 28 % glass tint on macOS 26) behind the row; text keeps its own colour on top. The accent never fills a control and never colours text, except the symbol on the selected row's tile (`accent-symbol`) and the recorder's border while recording.
- Hairlines (`hairline`) run edge to edge between the query and the list, above the actions menu and above the footer. The only other border is the 1 px `key-cap-edge` on a key cap.
- `running` marks a running app as a 6 pt dot with the tooltip "Running"; it is never the only signal (the first action reads "Switch", not "Open").
- `danger` is text only, in Settings captions. It is 4.5:1 on `panel-raised` in light mode only at 13 pt semibold or larger, so keep error captions under the field they describe and never alone.
- `panel.accentColor` takes `mestre`, `system`, hex, rgb(), hsl() or a CSS name. A value that does not parse falls back to the system accent and shows the `danger` caption in Settings.

## Type

San Francisco, through the system font. One large size (the query at 20 pt) and a short ladder below it: `row-title` 14 medium, `subtitle` and `action` 13, `kind` and `footer` 12, `section` 11 semibold. Key caps are SF Rounded (`key-cap`) so ⌘ ⌥ ↩ sit evenly. Settings fields and the config path are `field-mono`. `panel.queryFontSize` scales only the query and the search glyph (0.8 ×); the rest of the ladder is fixed so rows stay 42 pt.

## Spacing and size

The panel is 720 × 52 pt idle, and grows downward from a fixed top edge as rows arrive: height = `field-height` + 1 + rows × `row-height` + 16 + headers × 24 + 1 + `footer-height`, capped at `max-rows` (8). Rows pad 10 horizontally and gap 10 after a 28 pt icon; the title and the inline subtitle are 8 apart; the query row and the footer pad 16. The list and the actions block inset 8. Every pitch is listed under spacing with the element that uses it; nothing snaps to a grid.

The panel is centred horizontally on the screen under the mouse, its top at 22 % of the visible frame (`panel.verticalPosition`). Still proposed: a `panel.screen` key (`mouse` · `active` · `primary`) and re-clamping into the visible frame on screen-parameter changes.

## Radius

Every corner is continuous (a squircle). Radius tracks nesting: `radius-panel` 12 → `radius-row` 8 → `radius-tile` 7 → `radius-action` 6 → `radius-cap` 5. A child is never rounder than its parent.

## Material and depth

Default `panel.material` is `glass` (NSGlassEffectView on macOS 26, `.popover` vibrancy before it). `clearGlass`, `popover`, `hud`, `sidebar`, `menu`, `window` and `none` are the other choices; `none` drops the blur and paints `panel`. There is one shadow, the window's. Glass over a busy wallpaper costs legibility, so the selection tint is 28 % there instead of 16 %, key caps carry a border, and `none` is the documented escape hatch.

## Motion

None, by design. The panel appears with the system utility-window behaviour and resizes without animation. Do not add `withAnimation`; measure if you must.

## Iconography

- Row icons are 28 pt (`panel.iconSize`): the app's own icon, the Finder icon for files, a colour swatch, an emoji, or an SF Symbol at half the icon size, medium, on an `IconTile`.
- Symbols are SF Symbols, one per command or feature, chosen for the noun (`cup.and.saucer` keep awake, `moon.zzz` sleep, `lock` lock screen, `plus.forwardslash.minus` calculator). The fallback is `circle.dashed`.
- Actions carry a symbol at 13 pt in a 16 pt column; `circle` when none is declared.
- The menu-bar item and the footer glyph are `sparkle.magnifyingglass` as a template image; the menu-bar one swaps to `cup.and.saucer.fill` while keep-awake runs.
- The app icon is drawn in code (`scripts/make-icon.swift`): a squircle at 0.225 × width, a −60° gradient from `mark-indigo` to `mark-violet`, a white "M" polyline and a `mark-spark` "+" at 80 %/80 %.

## Keyboard

Keys are intercepted by the panel before the text field, except while an input method is composing.

| Key | Does |
| --- | --- |
| ↑ ↓, ⌃P ⌃N | Move the selection; clamps at the ends, no wrap |
| ↩ | Runs the first action of the selected row |
| ⌘K | Opens the actions menu on the first action; ⌘K or esc closes it |
| esc | Closes the panel |
| ⌘↩, ⌘Q, ⌘H, ⌘⇧C, ⌘Y, ⌘⇧K, ⌘⌫ | Run the action with that id on the selected row, or beep |

⇥ scopes a feature or quicklink row (a chip before the field) and unfolds any other row's actions as chips; ⌫ on an empty field leaves a scope. Not done: `keys.escape` (esc always closes), `panel.screen`. No typing timer, ever.

## Components

Each component below has a live preview and a guideline. Panel surfaces: `Panel`, `QueryField`, `ResultRow`, `IconTile`, `KindBadge`, `SectionHeader`, `KeyHint`, `Footer`, `ActionsMenu`, `EmptyState`, `HomeScreen`. Windows: `MenuBarMenu`, `Welcome`, `SettingsRow`, `HotKeyRecorder`. The previews are static renditions in HTML of the SwiftUI and AppKit views, styled only by the tokens and `components/bundle.css`; there is no JavaScript bundle because the product is Swift.
