# Configuration

All settings live in `~/.config/mestre/config.json` (or `$XDG_CONFIG_HOME/mestre/config.json`).
The app writes it on first launch, updates it when you change something in Settings,
and reloads it as soon as you save it in an editor. Every key is optional.

```json
{
  "hotKey": "option+space",
  "keys": {},
  "hotkeys": { "hyper+t": "Terminal", "cmd+shift+f": "Firefox", "hyper+v": "feature:clipboard" },
  "quicklinks": [
    { "name": "GitHub search", "url": "https://github.com/search?q={query}", "keyword": "gh" },
    { "name": "Mestre repo", "url": "https://github.com/fabioop/mestre" }
  ],
  "aliases": { "ff": "Firefox", "code": "com.microsoft.VSCode" },
  "quickKeys": { "enabled": true, "keys": { "sl": "sleep" } },
  "panel": {
    "width": 720,
    "fieldHeight": 52,
    "rowHeight": 42,
    "iconSize": 28,
    "maxVisibleRows": 8,
    "verticalPosition": 0.22,
    "cornerRadius": 12,
    "queryFontSize": 20,
    "material": "glass",
    "appearance": "system",
    "accentColor": "mestre",
    "subtitles": "selected",
    "showFooter": true,
    "peekNextRow": true,
    "toastSeconds": 1.5,
    "compact": false,
    "completion": "scope"
  },
  "home": {
    "sections": ["recent", "features", "commands"],
    "recentCount": 5,
    "hidden": []
  },
  "search": {
    "appDirectories": ["/Applications", "~/Applications"],
    "includeSystemApps": false,
    "scanDepth": 2,
    "maxResults": 8,
    "watchFolders": true,
    "refreshIntervalSeconds": 0
  },
  "ranking": {
    "usageWeight": 1,
    "showRecents": true,
    "runningBoost": 5,
    "providers": { "settings": { "bias": -200 } },
    "budgetMs": 5
  },
  "calculator": {
    "enabled": true,
    "precision": 10
  },
  "commands": {
    "enabled": true,
    "confirmDestructive": true,
    "hidden": []
  },
  "settingsPanes": {
    "enabled": true,
    "hidden": []
  },
  "processes": {
    "enabled": true,
    "keyword": "kill"
  },
  "keepAwake": {
    "enabled": true,
    "keyword": "awake",
    "allowDisplaySleep": false,
    "durationsMinutes": [15, 30, 60, 120, 240],
    "whileRunningApps": [],
    "whileCharging": false,
    "endWhenBatteryBelow": 0,
    "menuBarIcon": true
  },
  "shortcuts": {
    "enabled": true,
    "refreshIntervalSeconds": 300
  },
  "webSearch": {
    "enabled": true,
    "engine": "https://duckduckgo.com/?q={query}"
  },
  "clipboard": {
    "enabled": true,
    "keyword": "clip",
    "maxItems": 500,
    "maxAgeDays": 30,
    "maxTextBytes": 1000000,
    "pollIntervalSeconds": 0.5,
    "excludeApps": ["com.1password.1password", "com.bitwarden.desktop"]
  },
  "snippets": {
    "enabled": true,
    "dateFormat": "yyyy-MM-dd",
    "timeFormat": "HH:mm",
    "expansion": { "enabled": false, "excludeApps": ["com.apple.Terminal"] },
    "items": [
      { "name": "Signature", "keyword": "/sig", "text": "Best,\nFabio" },
      { "name": "Today", "text": "{date} {time}" },
      { "name": "Quote", "text": "> {clipboard}\n\n{cursor}" }
    ]
  },
  "paste": {
    "delaySeconds": 0.05,
    "cursorDelaySeconds": 0.1
  },
  "emoji": {
    "enabled": true,
    "keyword": "emoji",
    "prefix": ":",
    "recentCount": 24
  },
  "paths": {
    "enabled": true,
    "showHidden": false,
    "maxResults": 20
  },
  "colors": { "enabled": true, "formats": ["hex", "rgb", "hsl", "swiftui"], "names": false },
  "bookmarks": {
    "enabled": true,
    "keyword": "bm",
    "searchEverywhere": false,
    "penalty": 10,
    "minimumLength": 2,
    "openInSourceBrowser": true,
    "excludeBrowsers": []
  },
  "dictionary": {
    "enabled": true,
    "keyword": "define",
    "maxLines": 6,
    "debounceSeconds": 0.15
  },
  "files": {
    "enabled": true,
    "keyword": "file",
    "folders": ["~"],
    "excludedFolders": ["~/Library", "~/.Trash"],
    "maxResults": 20,
    "debounceSeconds": 0.15,
    "minimumLength": 2
  },
  "windows": {
    "enabled": true,
    "gap": 0,
    "hidden": [],
    "listWindows": true,
    "listRefreshSeconds": 2
  },
  "scripts": { "enabled": true, "items": [
    { "name": "Notes", "keyword": "nt", "command": "~/bin/notes.sh", "mode": "once", "needs": ["fs:~/Notes"] }
  ] },
  "onboarding": { "showWelcome": true },
  "debug": {
    "logTimings": false
  }
}
```

First launch writes a file of notes only, so every key keeps its default until you set it; the
file is written again only when a setting changes. `Show Default Config` (a command, also
Settings › General) opens every default with a one-line note per section; the same from a shell:

```bash
build/Mestre.app/Contents/MacOS/Mestre --show-config --default --docs
```

Without `--default` it prints the settings in force.

- `hotKey`: modifiers `cmd`, `option` (or `alt`), `ctrl`, `shift`, `hyper` (all four, as a
  Caps Lock remap produces), plus a key: a single character, `space`, `return`, `tab`,
  `escape`, `delete`, arrows (`up`…), or `f1`–`f20`.
- `hotkeys`: global shortcut → app name or bundle identifier, command id or title,
  `window:<layout>`, or `feature:<id>`. An app opens or comes forward without showing the panel;
  `feature:<id>` opens the panel on that feature and closes it when pressed again, e.g.
  `"hyper+v": "feature:clipboard"`. Feature ids: `clipboard`, `emoji`, `files`, `paths`,
  `bookmarks`, `dictionary`, `keepAwake`, `processes`, `colors`, `windows`. Shortcuts another
  app already owns are reported in Settings.
- `keys`: overrides for what each key does inside the panel, in the same combo format as
  `hotKey`, e.g. `"keys": {"moveUp": ["up", "ctrl+k"], "quit": "cmd+w"}`. Names come from one
  action table: the panel's own (`moveUp`, `moveDown`, `open`, `close`, `actions`) and every
  action a provider declares (`quit`, `reveal`, `copyPath`, `quickLook`, `paste`, `delete`…).
  Settings › Keys lists every action with its title, name, providers and keys, and the ⌘K
  menu shows each action's name next to its key, so what you see is what you bind. Defaults:
  `moveUp` up, ctrl+p · `moveDown` down, ctrl+n · `open` return · `close` escape ·
  `actions` cmd+k · `complete` tab · `moveLeft` left · `moveRight` right (only while chips are open) ·
  `back` delete (only to leave a scope) · `quit` cmd+q · `hide` cmd+h · `reveal` cmd+return · `copyPath` cmd+shift+c ·
  `quickLook` cmd+y. Your overrides win over defaults; a bound key is consumed before the text
  field sees it, so avoid binding plain letters.
- `quicklinks`: a list of `{name, url, keyword}`. A URL containing `{query}` is a search:
  type the keyword (one lowercase word) and then the words, and they are percent-encoded into
  the URL; picking a search link by name completes the box to its keyword. While the query
  starts with a keyword only that quicklink answers, so avoid keywords that are app names.
  Links without a placeholder open as they are; a URL without a scheme gets `https://`.
- `aliases`: shorthand → app name or bundle identifier. Typing the alias exactly puts that app
  first, even above an app whose name matches exactly, and the row says why ("alias ff").
- `quickKeys`: two-letter keys for commands and features, generated from their titles ("ls"
  for Lock Screen) unless `keys` names one; shown as a cap on the row. Typing a key exactly
  brings up its row, then ↩ runs it. A key you set in `keys` goes first; a generated key goes
  first unless another row's name starts with those letters, so "sl" keeps Slack on top and
  never sleeps the Mac by surprise. `enabled: false` hides them.
- `scripts`: keyword-triggered scripts that print rows as script-filter JSON
  (`{"items": [{"title", "subtitle", "arg", "uid", "icon": {"path"}, "valid", "autocomplete",
  "match"}], "rerun"}`), the format many launcher scripts already print, so they port unchanged. Each item has `name`, `keyword`,
  `command` (an executable, run with the query as its argument; or a shell line when it contains
  a space, run as written with the query in `$1` and `MESTRE_QUERY` for it to use or ignore), `mode` (`once`: run when the keyword is entered, Mestre filters the rows as
  you type by `match` or title; `perKeystroke`: run on every change after `debounceMs`),
  `cacheSeconds` (reuse the last rows between sessions), `action` (a command run on Return
  with the row's `arg` as `$1`; otherwise a URL or path argument opens and anything else is
  copied; a path to an app bundle or an executable is copied too, never launched), `needs`
  (what it touches, shown as chips: `clipboard`, `fs:~/Documents`, `network`) and
  `timeoutSeconds` (a longer run gets SIGTERM, then SIGKILL; default 10). A script may print
  up to 500 rows and 4 MB; while a newer run is in flight the last rows stay. Scripts run off the main
  thread; a run that fails, prints something else or times out says so in the panel.
- `panel`: geometry and look. `verticalPosition` is the top edge as a fraction of screen
  height; `material` is `glass` (Liquid Glass, macOS 26), `clearGlass`, or one of the classic
  blurs `popover`, `hud`, `sidebar`, `menu`, `window`, `none`.
  `maxVisibleRows` is how many rows show before scrolling; `search.maxResults` is how many
  results exist at all. `iconSize` is the row icon, never taller than the row. `appearance` is
  `system`, `light` or `dark`; `accentColor` is `mestre` (the brand violet, adjusted per
  appearance), `system` or empty for the system accent, or a hex value / CSS name for the
  selection highlight. `showFooter` draws the bar under the list that names the feature owning
  the query and the selected row's keys (Open ↩, Actions ⌘K). `peekNextRow` shows half of the
  next row when more results exist than fit, so the overflow is visible without a scrollbar.
  `toastSeconds` is how long a confirmation such as "Path copied" stays in the footer (0 = none).
  `compact` keeps the panel to the field and the footer until something is typed, instead of the
  home screen. `completion` is what choosing a feature or a search quicklink does: `scope`
  (default) turns it into a chip before the field and what you type is its query, ⌫ on an empty
  field leaves it; `text` types its keyword into the field. `subtitles` is
  when a row's second line is drawn: `selected` keeps metadata (a folder, "Browser", a URL,
  "alias ff") on the selected row only and shows content (an expression, a keyword, a clipboard
  entry's age) everywhere, so the list reads as one line per item; `always` shows every second
  line. A choice that isn't one of the listed values falls back to the default.
- `home`: what an empty query shows. `sections` in order from `recent`, `features`, `commands`;
  `recentCount` apps; `hidden` feature or command ids.
- `ranking.usageWeight`: how much launch history (frequency × recency) lifts an app; 0 ranks by
  name match only. `showRecents` lists recently launched apps while the search box is empty.
  `providers` is an advanced setting that weighs one provider against the others when results
  are merged: `scale` multiplies its match scores and `bias` is added; pinned rows (the calculator, a
  keyword's own rows) are left alone. The default `"settings": {"bias": -200}` keeps System
  Settings panes under any app that matches; `{"scale": 1}` ranks them by match alone. Your
  entries are added to that default. Weights apply after each provider has picked its own top
  rows, so they reorder the merged list rather than widen one provider's share.
  `budgetMs` is how long a provider may take per keystroke before its worst time is shown in
  Settings (and logged when `debug.logTimings` is on). A matching alias is shown after the title, "Firefox (ff)", so it can be learned.
- `watchFolders`: re-index the moment an app folder changes, so a fresh install shows up
  immediately. `refreshIntervalSeconds` is an optional periodic fallback (0 = off).
- `commands`: `enabled`, `confirmDestructive` (Restart, Shut Down, Log Out, Empty Trash ask
  first) and `hidden` (command ids to drop, also from hotkeys). Commands can be `hotkeys`
  targets by id or title, e.g. `"hyper+l": "lockScreen"`; an installed app of the same name
  wins. Some commands drive Finder or System Events through
  AppleScript; macOS asks once for Automation consent.
- `settingsPanes`: `enabled` and `hidden` (pane titles or bundle identifiers, case-insensitive).
  Panes are discovered from the system's own Settings extensions; known ones get the titles
  System Settings shows plus search terms ("dark mode" finds Appearance), new ones a title
  derived from their identifier.
- `keepAwake`: `enabled`, `keyword`, `allowDisplaySleep` (sessions then prevent only system
  sleep), `durationsMinutes` (the timed rows), `whileRunningApps` (names or bundle ids that keep
  the Mac awake while running), `whileCharging`, `endWhenBatteryBelow` (percent, 0 = never),
  `menuBarIcon`. A session you start outranks the triggers; after it ends a trigger that still
  holds takes over. Keeping awake with the lid closed needs `pmset` changes and is not done.
- `processes`: `enabled` and the trigger `keyword` (one word, default `kill`). While the
  query starts with the keyword only processes are listed: those you can signal, biggest
  physical footprint first (the number Activity Monitor shows).
- `shortcuts`: `enabled` and `refreshIntervalSeconds`, how old the list may be when the panel
  opens before it is re-read (0 = only at launch). Uses the `shortcuts` command line tool.
- `webSearch`: `enabled` and `engine`, a URL with `{query}` (e.g. `https://www.google.com/search?q={query}`).
  "Search the web for …" is always the last row; a typed address ("github.com/x",
  "localhost:3000") ranks above prefix matches but below an app whose name matches exactly.
- `clipboard`: `enabled`, `keyword`, `maxItems`, `maxAgeDays` (0 = no expiry), `maxTextBytes`,
  `pollIntervalSeconds` (the pasteboard has no change notification, so its change counter is
  read this often) and `excludeApps` (bundle identifiers; the defaults
  cover common password managers; contents marked concealed or transient are never kept).
  History is stored in plain text, owner-only, under
  `~/Library/Application Support/Mestre/Clipboard`; images as PNG files named by content hash.
- `snippets`: `enabled`, `items` (`{name, text, keyword}`), `dateFormat`, `timeFormat`.
  Placeholders: `{date}`, `{time}`, `{datetime}`, `{date:EEEE d MMMM}`
  (any Unicode format), `{clipboard}`, `{uuid}`, `{cursor}` (where the caret ends up).
  Pasting needs Accessibility access; otherwise ↩ copies. `expansion.enabled` turns on
  type-anywhere expansion of keywords (2+ characters, no spaces, preceded by a space or
  punctuation) through a listen-only keyboard event tap. It needs Input Monitoring as well
  as Accessibility; only the last few typed characters are held in memory, nothing is
  stored; input methods (Japanese, Chinese…) are left alone; `expansion.excludeApps` lists
  bundle identifiers to skip. Avoid keywords that are prefixes of other keywords.
- `paste`: `delaySeconds` between closing the panel and ⌘V, `cursorDelaySeconds` between ⌘V
  and moving the caret to `{cursor}` (slow apps need more). Pasting replaces what was on the
  pasteboard, after recording it in the history.
- `emoji`: `enabled`, `keyword`, `prefix` (`":"`; empty disables the shorthand; while the
  query starts with it only emoji are listed) and `recentCount`. The list is bundled (Unicode names plus common aliases); skin-tone variants
  and most flags are not included yet.
- `colors`: `enabled`, `formats` (rows and order: hex, rgb, hsl, swiftui) and `names` (treat
  CSS colour names as colours; off so "tan" or "orange" still find apps).
- `bookmarks`: `enabled`, `keyword`, `searchEverywhere` (bookmarks also answer ordinary
  queries of `minimumLength`+ characters, ranked `penalty` below apps), `openInSourceBrowser`,
  `excludeBrowsers` (chrome, brave, edge, chromium, vivaldi, arc, firefox). Files are re-read
  when the panel opens and they changed since; Firefox's database is read in place.
- `onboarding`: `showWelcome` — the welcome window at launch. The app turns it off after the
  first time; the status menu's "Welcome Guide" and setting it back to `true` show it again.
- `dictionary`: `enabled`, `keyword`, `maxLines`, `debounceSeconds`. Uses the dictionaries
  enabled in Dictionary.app; lookups run off the main thread after the pause.
- `paths`: `enabled`, `showHidden` (dot files; typing a `.` prefix shows them anyway) and
  `maxResults` for folder browsing. Folders list before files; packages (.app) open like files. Listings are read off the main thread and cached for a few seconds.
- `files`: `enabled`, `keyword`, `folders` searched, `excludedFolders`, `maxResults`,
  `debounceSeconds` (pause after typing before Spotlight is asked) and `minimumLength`. Every word must appear
  in the file name; newest-modified first. Needs Spotlight indexing on.
- `windows`: `enabled`, `gap` (points between windows and screen edges), `hidden` (layouts
  kept out of the results), `listWindows` (open windows as results, independent of the
  shortcuts) and `listRefreshSeconds` (how often the list may be re-read on panel open). Layout shortcuts live in `hotkeys` with `window:` targets and
  ⌃⌥ defaults; override with `"hyper+h": "window:leftHalf"` or disable a
  default with `"ctrl+option+left": ""`. Layout ids: leftHalf, rightHalf, topHalf,
  bottomHalf, leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds, topLeft,
  topRight, bottomLeft, bottomRight, maximize, almostMaximize, center, restore, nextDisplay,
  previousDisplay.
- `calculator`: `enabled` and `precision` (significant digits). A comma followed by three
  digits is a thousands separator; otherwise it is a decimal point (`3,5*2` = 7).
- `includeSystemApps`: off by default so results show the apps you installed, not
  everything under /System/Applications. Turn it on to search Apple's apps too.
