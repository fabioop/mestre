# What is visible, and when

The panel has five states. Each row of this table is a rule; the column says which element shows. "Selected" means the row under the highlight. Rules marked **P** are proposed and differ from the shipped code.

## Panel states

| State | Query row | List | Section headers | Actions menu | Footer |
| --- | --- | --- | --- | --- | --- |
| Idle, home off | placeholder | hidden, panel is 52 pt | — | — | — |
| Idle, home on | placeholder | Recent · Features · Commands | yes | — | "Mestre" · the selected row's keys |
| Typing, results | query + caret | up to `max-rows`, then scroll | only when a provider groups | — | owner or "Mestre" · keys |
| Typing, no results | query | hidden | — | — | hidden; one `EmptyState` line instead |
| ⌘K open | query | the whole list, selection kept | "Actions" | yes, below a hairline | keys, caps also in the menu |
| ⇥ on a row | query, or a scope chip | the list, with the selected row's actions as chips under it | — | — | "Choose ← →", "Run ↩" |

## Per element

| Element | Unselected row | Selected row | Rule |
| --- | --- | --- | --- |
| Icon | yes | yes | Always; it is the fastest thing to scan. |
| Title | yes | yes | One line; keeps its width, the subtitle truncates. |
| Running dot | yes | yes | Only for a running app or an active keep-awake session. |
| Subtitle: content (expression, keyword, clipboard age, feature hint, definition) | yes | yes | A second line that is content stays. |
| Subtitle: metadata (folder, "Browser", "Window", "System Settings") | no | yes | Metadata earns its place only when the user is about to act (`panel.subtitles: selected`). |
| Alias that matched, "(ff)" after the title | yes | yes | Always, so the alias can be learned; it is the only match reason the panel explains. |
| KindBadge | yes | yes | Always at the trailing edge; nothing else ever sits there. |
| Hints ("Switch ↩", "Actions ⌘K") | — | — | In the footer, for the selected row; the second hint only when it has more than one action. |
| Section header | — | — | Only on the home screen and when a provider groups results; never for a single section. |

## The list

- **Order is fixed at first paint.** Late providers append below; nothing moves above the selection. The calculator pins to the top when the query parses as an expression, the web fallback pins to the bottom, a quick key typed exactly brings up its row, first unless another row's name starts with those letters; one you set is always first.
- **Exact title, then prefix, then word-start, then usage.** `ranking.usageWeight` scales the tie-break only; `runningBoost` lifts running apps among equals. A query that parses as an expression never matches app names (so "2fa" is an app, "2+fa" is not).
- **Prefer nothing to nonsense.** A fuzzy match below the threshold is dropped rather than shown; the user reads an `EmptyState` that names the query.
- **Eight rows, then scroll.** `panel.maxVisibleRows` and `search.maxResults` default to 8 so the panel never covers more than 445 pt. Moving onto the first row of a section scrolls the header into view.
- **Home is a menu, not a feed.** Recent (5) · Features · Commands in that order, each hideable through `home.hidden` and `home.sections`; `panel.compact` drops it entirely until something is typed. Each feature and command carries its quick key.

## The footer

- Left: a Mestre glyph and the feature that owns the query ("Clipboard History", "Calculator"), or "Mestre". It is the only place the panel names a mode, and it never stacks.
- Right: "<default action> ↩" and "Actions ⌘K" for the selected row, in `footer` + `KeyHint`. Nothing when the row has no action (a Calculator feature row).
- Hidden with the list (empty state, idle with home off) and by `panel.showFooter: false`.

## Menus

- **The actions menu is flat and stable.** Provider order, never usage order; the first action is the default and shows ↩, the rest show their own binding or nothing. ⇥ unfolds the same actions as chips under the row for the quick case.
- **Modifier shortcuts work without the menu.** ⌘↩ reveals, ⌘Q quits, ⌘⇧C copies the path on any row that declares the action; the menu is for discovery, not for the common case.
- **The menu-bar menu has seven items** and never grows: Open · Rebuild Index · — · Settings · Edit Config · Welcome · — · Quit. Features never get menu items; they live in the panel.
- **No nested menus anywhere.** A command that needs a parameter (keep awake, window layout) takes it as typed text, not as a submenu.

## Scope

A scope chip (a feature or quicklink entered with ⇥ or ↩) sits before the field; ⌫ on an empty field pops it.

## Settings

- One page per config section, in the order of the config file; the sidebar is the table of contents of `config.json`.
- A field edits one key and shows its unit (`pt`, `rows`, `ms`) after it. A behaviour is a named choice (`material: glass | popover | none`), not a numeric knob with an invented scale. The one exception is `ranking.providers`, an advanced setting with a default that needs no tuning.
- Every page ends with the config path so the user knows where the value went.
- An error caption sits directly under its field, in `danger`, and the fallback the app chose is stated ("using the system accent").
