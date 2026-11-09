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
    "theme": "mestre",
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
    "hidden": [],
    "layout": "list",
    "tiles": ["keepAwake", "clipboard", "sleep"],
    "tileHeight": 156
  },
  "search": {
    "appDirectories": ["/Applications", "~/Applications"],
    "includeSystemApps": true,
    "scanDepth": 2,
    "maxResults": 8,
    "watchFolders": true,
    "refreshIntervalSeconds": 0
  },
  "ranking": {
    "usageWeight": 1,
    "showRecents": true,
    "runningBoost": 5,
    "systemAppPenalty": 2,
    "providers": { "settings": { "bias": -200 }, "contacts": { "bias": -25 }, "menus": { "bias": -15 } },
    "budgetMs": 5
  },
  "calculator": {
    "enabled": true,
    "precision": 10,
    "units": true,
    "currency": true,
    "defaultCurrency": "",
    "ratesMaxAgeHours": 24,
    "ratesURL": "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/eur.min.json",
    "timeZones": true,
    "dates": true,
    "cityAliases": {},
    "worldClocks": [],
    "suggestions": 6,
    "suggestedPlaces": ["utc", "london", "new york", "san francisco", "tokyo"],
    "suggestedCurrencies": ["USD", "EUR", "GBP", "JPY", "CHF"],
    "suggestedUnits": ["km", "mi", "m", "ft", "in", "cm", "kg", "lb", "g", "oz", "°c", "°f", "l", "ml", "gal", "fl oz", "cup", "m²", "ft²", "ha", "ac", "km/h", "mph", "m/s", "kn", "GB", "MB", "TB", "KB", "min", "h", "s", "d", "wk"]
  },
  "commands": {
    "enabled": true,
    "confirmDestructive": true,
    "hidden": [],
    "volumeStep": 10,
    "quitAllExcept": []
  },
  "settingsPanes": {
    "enabled": true,
    "hidden": []
  },
  "processes": {
    "enabled": true,
    "keyword": "kill",
    "ports": true
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
  "bluetooth": {
    "enabled": true,
    "keyword": "pair",
    "closeOnConnect": true,
    "connectTimeoutSeconds": 30,
    "showUnknownDevices": false
  },
  "media": {
    "enabled": true,
    "keyword": "media",
    "nowPlaying": true,
    "players": ["com.apple.Music", "com.spotify.client"],
    "method": "keys",
    "closeOnControl": true,
    "playPauseWords": ["play", "pause"],
    "nextWords": ["next"],
    "previousWords": ["previous", "prev"]
  },
  "shortcuts": {
    "enabled": true,
    "refreshIntervalSeconds": 300
  },
  "scripts": {
    "enabled": true,
    "keyword": "script",
    "directories": ["~/.config/mestre/scripts"],
    "searchEverywhere": true,
    "timeoutSeconds": 30,
    "extraPath": ["/opt/homebrew/bin", "/usr/local/bin"],
    "editor": "",
    "hudSeconds": 2
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
  "contacts": {
    "enabled": true,
    "keyword": "contact",
    "searchEverywhere": true,
    "minimumLength": 2,
    "maxResults": 20,
    "defaultAction": "reveal",
    "callScheme": "tel",
    "messageScheme": "sms"
  },
  "dictionary": {
    "enabled": true,
    "keyword": "define",
    "maxLines": 6,
    "debounceSeconds": 0.15,
    "onPaste": true,
    "cards": true,
    "cardSenses": 4
  },
  "calendar": {
    "enabled": true,
    "keyword": "cal",
    "daysAhead": 7,
    "maxResults": 20,
    "excludeCalendars": [],
    "mergeDuplicates": true,
    "countdownMinutes": 60,
    "meetingHosts": ["zoom.us", "zoomgov.com", "meet.google.com", "teams.microsoft.com", "teams.cloud.microsoft", "teams.live.com", "teams.microsoft.us", "webex.com", "facetime.apple.com", "whereby.com"]
  },
  "reminders": {
    "enabled": true,
    "keyword": "remind",
    "listKeyword": "todo",
    "defaultList": "",
    "defaultTime": "09:00"
  },
  "translator": {
    "enabled": true,
    "keyword": "tr",
    "languages": [],
    "debounceSeconds": 0.3,
    "maxCharacters": 2000
  },
  "ocr": {
    "enabled": true,
    "clipboardImages": true,
    "languages": [],
    "recognitionLevel": "accurate",
    "keepLineBreaks": true,
    "maxImagePixels": 16000000
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
  "menus": {
    "enabled": true,
    "keyword": "menu",
    "searchEverywhere": false,
    "readOnOpen": false,
    "maxDepth": 4,
    "maxItems": 3000,
    "readTimeoutSeconds": 2,
    "cacheSeconds": 5
  },
  "updates": { "check": true, "channel": "stable", "intervalHours": 24 },
  "onboarding": { "showWelcome": true },
  "debug": {
    "logTimings": false
  }
}
```

The welcome window can give `hotKey` Spotlight's ⌘Space. That also turns off Spotlight's own shortcut
in macOS, which is the one change Mestre makes outside its files; the same screen gives it back, or
turn it on again in System Settings › Keyboard › Keyboard Shortcuts › Spotlight. Uninstalling Mestre
doesn't restore it.

Settings edits this file and nothing else, so copying the `~/.config/mestre` folder to another Mac
brings everything across except macOS permissions, which that Mac has to grant again. Settings covers
what most people change. Technical keys live only in the file: wait times and polling intervals,
`search.scanDepth`, `search.watchFolders`, `search.refreshIntervalSeconds`, `ranking.runningBoost`,
`ranking.systemAppPenalty`, `ranking.providers`, `ranking.budgetMs`, `quickKeys.keys`,
`clipboard.maxTextBytes`, `clipboard.pollIntervalSeconds`, `files.debounceSeconds`, `files.minimumLength`,
`dictionary.debounceSeconds`, `calculator.ratesMaxAgeHours`, `calculator.ratesURL`, `calculator.cityAliases`, `calculator.worldClocks`, `calendar.maxResults`, `calendar.meetingHosts`, `translator.debounceSeconds`, `translator.maxCharacters`, `ocr` (except `ocr.clipboardImages`), `bookmarks.minimumLength`, `bookmarks.penalty`, `contacts.minimumLength`, `contacts.maxResults`, `contacts.callScheme`, `contacts.messageScheme`, `paste`,
`shortcuts.refreshIntervalSeconds`, `scripts.directories`, `scripts.timeoutSeconds`, `scripts.extraPath`, `scripts.editor`, `scripts.hudSeconds`, `windows.listRefreshSeconds`, `emoji.prefix`, `media.players`, the `media`
search words (`playPauseWords`, `nextWords`, `previousWords`), `updates`, and `debug`.

Each Settings page has a reset button, and General can reset everything. Resets keep your quicklinks,
snippets, aliases and how much clipboard history is kept, and save the previous file as `config.backup.json`, which Undo puts back.

`startup.launchAtLogin` registers Mestre as a login item when the file is read. Left out, it keeps
whatever macOS has now.

`updates` controls in-app updates. `check` looks for a new version every `intervalHours` (at least 1),
which is one request to GitHub; with it off, Check for Updates… in the menu bar still works. `channel`
is `stable` or `beta`, and `beta` also offers pre-releases. `feedURL` replaces the built-in update feed;
it must be `https`, and release builds only accept a feed signed with Mestre's update key.
Builds you make yourself have no update key, so they never check.

First launch writes a file of notes only, so every key keeps its default until you set it; the
file is written again only when a setting changes. `Show Default Config` (a command, also
All Options in Settings › General) opens every default with a one-line note per section; the same from a shell:

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
  `bookmarks`, `contacts`, `dictionary`, `calendar`, `reminders`, `translator`, `keepAwake`, `bluetooth`, `media`, `processes`, `colors`, `scripts`, `windows`, `menus`. Shortcuts another
  app already owns are reported in Settings.
- `keys`: overrides for what each key does inside the panel, in the same combo format as
  `hotKey`, e.g. `"keys": {"moveUp": ["up", "ctrl+k"], "quit": "cmd+w"}`. Names come from one
  action table: the panel's own (`moveUp`, `moveDown`, `open`, `close`, `actions`) and every
  action a provider declares (`quit`, `reveal`, `copyPath`, `quickLook`, `paste`, `delete`…).
  Settings › Shortcuts lists every action with its title, name and keys, and the ⌘K
  menu shows each action's name next to its key, so what you see is what you bind. Defaults:
  `moveUp` up, ctrl+p · `moveDown` down, ctrl+n · `open` return · `close` escape ·
  `actions` cmd+k · `complete` tab · `moveLeft` left · `moveRight` right (only while chips are open) ·
  `back` delete (only to leave a scope) · `quit` cmd+q · `hide` cmd+h · `reveal` cmd+return · `copyPath` cmd+shift+c · `copyText` cmd+t ·
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
  `toastSeconds` is how long a confirmation such as "Path copied" stays in the footer (0 = none;
  scripts then show their messages near the bottom of the screen for `scripts.hudSeconds`).
  `compact` keeps the panel to the field and the footer until something is typed, instead of the
  home screen. `completion` is what choosing a feature or a search quicklink does: `scope`
  (default) turns it into a chip before the field and what you type is its query, ⌫ on an empty
  field leaves it; `text` types its keyword into the field. `subtitles` is
  when a row's second line is drawn: `selected` keeps metadata (a folder, "Browser", a URL,
  "alias ff") on the selected row only and shows content (an expression, a keyword, a clipboard
  entry's age) everywhere, so the list reads as one line per item; `always` shows every second
  line. A choice that isn't one of the listed values falls back to the default.
  `theme` names a theme file: `mestre` (the panel's own look), `ulm`, `putty`, `tiles`,
  `micro`, or your own (see [Themes](#themes)). While a theme is active its
  values win over `material`, `accentColor`, `cornerRadius`, `fieldHeight` and `queryFontSize`;
  what it leaves out keeps your value. `appearance` is `system` (default, follows macOS and switches
  with it), `light` or `dark`, and also picks which palette a theme draws.
- `home`: what an empty query shows. `sections` in order from `recent`, `features`, `commands`;
  `recentCount` apps; `hidden` feature or command ids. `layout` is `list` or `tiles`, a dashboard of
  the clock and date (as of when the panel opened), power, up to four recent apps and up to three
  feature or command ids from `tiles`, first one widest; `tileHeight` is one row of tiles, at least 124. Below a `panel.width` of 480 the list stands in. Arrow
  keys and ⇥ move between tiles, Return opens one and ⌘K shows its actions. It works with any theme and starts no timer.
- `ranking.usageWeight`: how much launch history (frequency × recency) lifts an app; 0 ranks by
  name match only. `showRecents` lists recently launched apps while the search box is empty.
  `providers` is an advanced setting that weighs one provider against the others when results
  are merged: `scale` multiplies its match scores and `bias` is added; pinned rows (the calculator, a
  keyword's own rows) are left alone. The default `"settings": {"bias": -200}` keeps System
  Settings panes under any app that matches; `{"scale": 1}` ranks them by match alone. Contacts
  (`-25`) and menu items (`-15`) found by an ordinary search sit below an app's own score. Your
  entries are added to that default. Weights apply after each provider has picked its own top
  rows, so they reorder the merged list rather than widen one provider's share.
  `budgetMs` is how long a provider may take per keystroke before its worst time is shown in
  Settings (and logged when `debug.logTimings` is on). A matching alias is shown after the title, "Firefox (ff)", so it can be learned.
- `watchFolders`: re-index the moment an app folder changes, so a fresh install shows up
  immediately. `refreshIntervalSeconds` is an optional periodic fallback (0 = off).
- `commands`: `enabled`, `confirmDestructive` (Restart, Shut Down, Log Out, Empty Trash, Eject
  All Disks and Quit All Apps ask first) and `hidden` (command ids to drop, also from hotkeys;
  `setVolume` drops the "volume 30" row). `volumeStep` is how many points Volume Up and Volume
  Down move (1–100, default 10); "volume 30" (or "vol 30%") sets a level. `quitAllExcept` lists
  app names or bundle ids Quit All Apps leaves running; Finder and Mestre always stay, and apps
  with unsaved work still ask. Toggle Wi-Fi uses CoreWLAN (no permission, unless System
  Settings requires an administrator for Wi-Fi); Toggle Hidden Files flips Finder's
  `AppleShowAllFiles` and relaunches Finder; Hide Other Apps keeps the frontmost app. Show
  Desktop and Do Not Disturb have no public API and are not offered. Commands can be `hotkeys`
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
  `menuBarIcon` (a dot appears beside the M in the menu bar while active). A session you start outranks the triggers; after it ends a trigger that still
  holds takes over. Keeping awake with the lid closed needs `pmset` changes and is not done.
- `processes`: `enabled` and the trigger `keyword` (one word, default `kill`). While the
  query starts with the keyword only processes are listed: those you can signal, biggest
  physical footprint first (the number Activity Monitor shows). `ports` (default on) makes
  `kill :3000` or `kill port 3000` list the processes listening on that TCP port instead,
  read in-process with libproc, off the main thread; only your own processes show up.
- `bluetooth`: `enabled` and the trigger `keyword` (one word, default `pair`). While the query
  starts with the keyword only the devices this Mac is paired with are listed: devices to connect
  first, audio before the rest and then the one Mestre connected most recently, connected ones last,
  so the keyword and Return can't disconnect the keyboard in use. `showUnknownDevices` also lists
  disconnected devices of no known kind, mostly an iPhone, Watch or Mac synced through iCloud. Return connects or disconnects; a device never paired goes through "Pair a New
  Device…", which opens Bluetooth settings. `closeOnConnect` closes the panel once connected and
  `connectTimeoutSeconds` is how long a connection may take before the row says it failed (at least 1).
  macOS asks for Bluetooth access the first time the keyword is typed, and not before.
- `media`: `enabled` and the trigger `keyword` (one word, default `media`), which lists what is
  playing and the Play/Pause, Next Track and Previous Track rows. The control rows are also
  ordinary results, found by `playPauseWords`, `nextWords` and `previousWords` and ranked by fuzzy
  match like the commands, so an app whose name starts with the same word still comes first on its
  own name. `method` is how a control is sent: `keys` (default) posts the system media keys, like
  the keyboard's ⏯ ⏭ ⏮, so whatever owns Now Playing reacts (Music, Spotify, a browser tab); macOS
  asks for Accessibility access on the first control. `player` sends an Apple Event to the running
  player instead (Music and Spotify only; macOS asks once for Automation consent per player).
  `closeOnControl` closes the panel after a control from an ordinary search; under the keyword it
  stays open so the now-playing row follows the change. `nowPlaying` shows the track, artist and
  state, read from the players' own change notifications (no polling). A player that was already
  playing before Mestre started is asked once, by Apple Event, the first time the keyword is typed
  while it runs; that is when macOS asks for Automation consent. `players` lists the bundle ids
  to listen to and control, in order of preference; only `com.apple.Music` and
  `com.spotify.client` are understood. No player is ever launched.
- `shortcuts`: `enabled` and `refreshIntervalSeconds`, how old the list may be when the panel
  opens before it is re-read (0 = only at launch). Uses the `shortcuts` command line tool.
- `scripts`: `enabled`, `keyword` (one word, default `script`), `directories` (folders whose
  scripts are listed, not their subfolders), `searchEverywhere` (titles also rank in ordinary
  searches), `timeoutSeconds` (a run is stopped after this, at least 1), `extraPath` (put
  before PATH, which an app opened from the Dock keeps to the system folders), `editor` (a
  bundle identifier or app path for Edit Script; empty opens the app the file's type opens in,
  or the default text editor when that app is a terminal that would run it) and `hudSeconds`
  (how long a script's message shows near the bottom of the screen when the footer can't show
  it: the panel has closed, `panel.showFooter` is off or `panel.toastSeconds` is 0; 0 shows
  none). See
  [Script commands](#script-commands).
- `webSearch`: `enabled` and `engine`, a URL with `{query}` (e.g. `https://www.google.com/search?q={query}`).
  "Search the web for …" is always the last row; a typed address ("github.com/x",
  "localhost:3000") ranks above prefix matches but below an app whose name matches exactly.
- `clipboard`: `enabled`, `keyword`, `maxItems`, `maxAgeDays` (0 = no expiry), `maxTextBytes`,
  `pollIntervalSeconds` (the pasteboard has no change notification, so its change counter is
  read this often) and `excludeApps` (bundle identifiers; the defaults
  cover common password managers; contents marked concealed or transient are never kept, and a
  snippet's `{clipboard}` is left empty for them, except for Mestre's own last paste).
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
  bundle identifiers to skip (by default the common terminals, where an expansion is a pasted command). Avoid keywords that are prefixes of other keywords.
- `paste`: `delaySeconds` between closing the panel and ⌘V, `cursorDelaySeconds` between ⌘V
  and moving the caret to `{cursor}` (slow apps need more). Pasting replaces what was on the
  pasteboard, after recording it in the history; the pasted text is marked transient, so other
  clipboard managers skip it, and nothing is pasted if another app came to the front meanwhile.
- `emoji`: `enabled`, `keyword`, `prefix` (`":"`; empty disables the shorthand; while the
  query starts with it only emoji are listed) and `recentCount`. The list is bundled (Unicode names plus common aliases); skin-tone variants
  and most flags are not included yet.
- `colors`: `enabled`, `formats` (rows and order: hex, rgb, hsl, swiftui) and `names` (treat
  CSS colour names as colours; off so "tan" or "orange" still find apps).
- `bookmarks`: `enabled`, `keyword`, `searchEverywhere` (bookmarks also answer ordinary
  queries of `minimumLength`+ characters, ranked `penalty` below apps), `openInSourceBrowser`,
  `excludeBrowsers` (chrome, brave, edge, chromium, vivaldi, arc, firefox). Files are re-read
  when the panel opens and they changed since; Firefox's database is read in place.
- `contacts`: `enabled`, `keyword`, `searchEverywhere`, `minimumLength`, `maxResults`, `defaultAction`,
  `callScheme`, `messageScheme`. `contact jane` searches names, nicknames, organisations, emails and phone
  numbers (any spacing: `contact 912 345`); accents don't matter and initials work (`contact js`). `contact `
  lists contacts by name, the first `maxResults` of them. macOS asks for access the first time you use the keyword; refused, the row opens
  System Settings › Privacy & Security › Contacts. Once access is granted, ordinary queries of
  `minimumLength`+ characters also find contacts, ranked below apps by `ranking.providers.contacts.bias` (`searchEverywhere`), by whole words only (no initials) and by phone
  only for a number typed as one, not arithmetic; they never ask for access. Actions (⌘K, or ⇥ for chips): Copy Email, Copy Phone, Email (`mailto:`), Call, Message,
  FaceTime and Open in Contacts (⌘↩); a card with several emails or phones gets one per value, and a key
  bound to an action id (`email`, `call`…) acts on the first. `defaultAction` is what Return does: `reveal`
  (Open in Contacts), `email`, `call`, `message`, `facetime`, `copyEmail` or `copyPhone`; a card without the
  value it needs opens in Contacts instead. `callScheme` is `tel` (a phone call through a nearby iPhone) or
  `facetime-audio`; `messageScheme` is `sms` or `imessage`. Contacts are read off the main thread at launch
  (when access was already granted) and again only when Contacts reports a change; they stay in memory, nothing
  is written to disk and photos aren't read.
- `onboarding`: `showWelcome` — the welcome window at launch. The app turns it off after the
  first time; the status menu's "Welcome Guide" and setting it back to `true` show it again.
- `dictionary`: `enabled`, `keyword`, `maxLines`, `debounceSeconds`, `onPaste`, `cards`, `cardSenses`. Uses the dictionaries
  enabled in Dictionary.app; lookups run off the main thread after the pause. With `onPaste`, pasting a
  single word (the whole field) shows its definition above every other result, without the keyword;
  typing it doesn't. With `cards`, `define <word>` shows the definition as cards in either home layout:
  the word and its pronunciation, then up to `cardSenses` senses (1–6) with an example each, and the origin.
- `calendar`: `enabled`, `keyword`, `daysAhead`, `maxResults`, `excludeCalendars` (`"Name"` in every
  account, or `"Account/Name"`), `mergeDuplicates` (an invitation in several accounts shows once), `countdownMinutes` (events starting
  within it say "in 20 min"; 0 turns it off) and
  `meetingHosts` (links that count as an event's meeting, also inside Outlook Safe Links). Events come from
  every account in System Settings › Internet Accounts: iCloud, Google, Microsoft 365 and Exchange (where
  Teams meetings live), Yahoo and CalDAV. An account's name also filters: `cal work`. `cal ` lists what's coming and more words
  filter it; `cal` with no space still finds the Calendar app. Return joins the meeting, or else opens the event.
  macOS asks for access the first time. Events are read off the main thread and again only when the calendars change.
- `reminders`: `enabled`, `keyword`, `listKeyword`, `defaultList`, `defaultTime`.
  `remind call mum fri 5pm` shows one row, "Call mum" due Friday at 17:00, and Return adds it to Reminders.
  The date comes out of the text on the Mac with a fixed grammar: `today`, `tonight`, `tomorrow`, a weekday
  (`fri`, `next fri`, `on sat`), a date (`12 nov`, `nov 12th`, `7 jan 2028`, `2026-11-20`), a time (`5pm`,
  `17:30`, `at 7`, `noon`; 1 to 7 with no am/pm is the afternoon, `05:00` is not), `morning`/`afternoon`/`evening`, and `in 2h`, `in 30 min`, `in 3 days`.
  A weekday that is today means today only when its time is still ahead. `!`, `!!` and `!!!` set low, medium and high
  priority, and `#name` picks a list (by name, or a prefix only one list has). Chips under the field show what was understood.
  A reminder with only a day is due at `defaultTime` ("09:00", "9am"); empty leaves it all-day, and so does a
  `defaultTime` that has already gone today. A reminder with a time also gets an alert then. `defaultList` names the list new
  reminders go to; empty uses the one macOS picks. `remind ` or `todo ` (`listKeyword`, both with the space; more words filter by title or
  list), lists open reminders due soonest first: Return completes one, ⌘↩ opens it in Reminders. `remind` with no space
  still finds the Reminders app. `"home": {"hidden": ["reminders"]}` leaves its row off the home screen; `feature:reminders` hotkeys still work. macOS asks for access the first
  time the keyword is typed; reminders are read off the main thread and again only when they change.
- `translator`: `enabled`, `keyword`, `languages`, `debounceSeconds`, `maxCharacters`. `tr hello` goes to
  the first of `languages` it isn't already in; empty uses the Mac's languages, then English.
  `tr >de hello` picks the target and `tr en>pt hello` both sides. Needs macOS 26. Translation is
  on-device and uses languages downloaded in System Settings › General › Language & Region › Translation Languages.
- `ocr`: text recognition with Vision, on this Mac; nothing is sent anywhere. `enabled` (off also
  hides the command), `clipboardImages`, `languages` (Vision codes such as `"en-US"`, `"pt-BR"`; empty
  detects the language; unknown codes are ignored), `recognitionLevel` (`accurate` or `fast`),
  `keepLineBreaks` and `maxImagePixels` (larger images are scaled down to this many pixels first, at least 250 000).
  **Copy Text from Screen** (`copy text`, `ocr`, `grab text`) closes the panel and shows the system's
  selection (drag a region, Space for a window, Esc to cancel). The selection goes to a PNG in a fresh
  owner-only temporary folder, deleted as soon as it's read. The text is copied to the clipboard and a toast
  says how many lines. `keepLineBreaks: false` joins the lines with spaces. macOS asks for Screen Recording the first
  time, and that first try captures nothing. Without the permission a capture shows only the desktop, and the toast says where to allow it.
  The toast appears near the bottom of the screen for `panel.toastSeconds`, because the panel is already closed.
  To run it from anywhere, bind the command's id: `"hotkeys": {"ctrl+option+t": "copyTextFromScreen"}`.
  With `clipboardImages` (on by default), each image that enters clipboard history has its text read once, in
  the background at low priority, and stored with the entry in `history.json`. Typing words from it
  (`clip invoice`) finds the image, its row shows the start of the text, and ⌘T (`copyText`) copies the text.
  Images already in the history are read once when this is on. The text is deleted with its entry.
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
- `menus`: menu item search. `menu export` lists the menu bar items of the app that was in
  front when the panel opened (the panel never takes focus, so it stays the frontmost app) and
  Return chooses one once the panel has closed. Each row shows the item, the menus above it
  ("File › Export") and its shortcut; the text matches the title or the whole path
  (`menu export pdf`). The keyword with nothing after it lists every item in menu order. The Apple
  menu, separators and disabled items are left out (a disabled item could not be chosen), as are
  items that only open a submenu. Keys: `enabled`, `keyword` (one word, default `menu`),
  `searchEverywhere` (menu items also in ordinary searches, below apps by `ranking.providers.menus.bias`; off by default because it
  reads the front app's whole menu bar on every panel open and a short word matches dozens of
  menu items), `readOnOpen` (read the menus as the panel opens so they are ready when the keyword
  is typed; off by default, which reads them when the keyword is first typed), `maxDepth` (menu levels read,
  counting the menu bar's own menus, 1–10), `maxItems` (items read at most, against menus that
  list every bookmark or history entry), `readTimeoutSeconds` (a read stops with what it has after
  this long, 0.1–30) and `cacheSeconds` (how long a read is reused when the panel opens again over
  the same app; switching apps always reads again). Menus are read through the Accessibility API,
  off the main thread, never while the feature is off or access is missing. Without access the
  keyword shows a row that asks for it; macOS shows its prompt only then, never at launch.
- `calculator`: `enabled` and `precision` (significant digits). A comma followed by three
  digits is a thousands separator; otherwise it is a decimal point (`3,5*2` = 7).
  `units` turns on `10 km to mi` and `72f in c` (also `in`, `as`, `em`, `para`) for length, mass, temperature,
  volume, area, speed, data and time. `currency` turns on `100 usd to eur` for every currency in use
  (ISO 4217, by code, symbol or name) plus `btc` and `eth`; `100 usd` alone goes to `defaultCurrency`, or the
  Mac's region when that is empty.
  While you type, up to `suggestions` rows answer early: an amount with no target converts to
  `defaultCurrency` then `suggestedCurrencies` (`15 ringgit`, `15 myr to`), or to the `suggestedUnits` in its
  category (`10 km` → mi, m, ft…; `30 c` → °F). A name being typed matches by its start: `15 ring` is MYR,
  `10 kilom` km, `1 ho` hours, `15 krona` both SEK and ISK, and the same after `to` (`15 myr to e`,
  `10 km to fe`). Currency names come from macOS in English and your Mac's language. Written together
  with the number, only a full name counts (`10km` yes, `4k` and `3d` stay app searches).
  Rates come from `ratesURL`: by default the free currency-api on jsDelivr (no key, every currency); the
  ECB's daily XML and open.er-api.com's JSON work too. They are downloaded only after such a query is
  typed, at most once per `ratesMaxAgeHours`, and again when `ratesURL` changes. The cached copy is used
  when offline, and the row says which day its rates are from.
  `timeZones` turns on `time in tokyo`, `now in new york`, `tokyo time`, `3pm lisbon in sf` and
  `15:30 utc to pst` (also `3 pm`, `15h30`, `noon`; `3pm tokyo` alone converts to your time). Places are the
  cities macOS knows (`Asia/Tokyo` → `tokyo`), full identifiers, `utc+5:30`, and a built-in list of
  nicknames, countries and abbreviations (`sf`, `nyc`, `la`, `bay area`, `uk`, `pst`, `cet`, `ist`…);
  `pst` means the US west coast, summer or not. `cityAliases` adds your own names, e.g.
  `{"home": "Europe/Lisbon", "office": "nyc"}`; a value is an identifier or any name Mestre knows.
  `worldClocks` is what `time` alone lists, e.g. `["home", "sf", "tokyo"]`; empty shows nothing, so
  `time` keeps finding Time Machine. A city name alone never becomes a row.
  Half-typed queries already answer, up to `suggestions` rows (at most 20; 0 waits for a full query): `3pm` alone
  converts to `worldClocks` and then `suggestedPlaces`, as does `3pm lisbon in`; a place being typed
  matches by its start, so `3pm lis` offers Lisbon, `3pm lisbon in new` offers New York and `time in to`
  offers Tokyo and Toronto. `3p` and `3a` count as 3 pm and 3 am.
  `dates` turns on date maths: `today + 90d`, `2026-01-01 + 3 weeks - 2d`, `now + 90 min`,
  `dec 25 - today`, `2026-12-25 - 2026-01-01`, `days until christmas`, `weeks since 2026-01-01`,
  `months between 2026-01-01 and dec 25`, `unix 1700000000` (13 digits are milliseconds), `now in unix`,
  and a lone `2026-12-25` or `25 dec` for its weekday. Units are `d`, `w`, `mo`, `y`, `h`, `min`, `s`
  and their words; dates are ISO (`2026-12-25`, `2026-12-25 15:00`) or a month name with a day
  (`dec 25`, `25 december 2027`); a date without a year is this year, except after `until`, where a
  day that has passed means next year. Results use your locale and calendar; the second copy action
  copies ISO 8601 for a moment and the bare number for a span. Everything runs offline. With
  `dates` on, `2026-12-25 - 2026-01-01` is a span of days, not a subtraction; `dates: false` (or
  single-digit parts such as `2026-1-1`) keeps the plain arithmetic.
- `includeSystemApps`: on by default, so Safari, Mail and the rest of /System/Applications
  come up alongside the apps you installed. Turn it off to search only `appDirectories`.
- `ranking.systemAppPenalty`: points taken off Apple's built-in apps, enough to settle a
  near-tie in favour of an app you installed ("m" → Mestre before Mail) but not to bury a
  better match. At the default `usageWeight` one launch outweighs it. 0 treats them alike.

## Script commands

Any file in `scripts.directories` with a title in its header is a result. The header is the one
[Raycast Script Commands](https://github.com/raycast/script-commands) use, so those scripts work
unchanged; `@mestre.` works in place of `@raycast.` for every key and wins when both are there.
Comments may start with `#`, `//` or `--`, so any language works. The script runs through its
shebang (or, without one, an interpreter picked by the extension: sh, bash, zsh, py, rb, js, swift,
applescript, pl, php), so it doesn't need its executable bit, in its own folder unless
`currentDirectoryPath` says otherwise. Hidden files and `*.template.*` files are skipped.

```bash
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Search GitHub
# @raycast.mode silent
# @raycast.packageName Developer Utils
# @raycast.icon 🐙
# @raycast.argument1 { "type": "text", "placeholder": "Query", "percentEncoded": true }

open "https://github.com/search?q=$1"
```

Save it as `~/.config/mestre/scripts/search-github.sh`; the folder is watched, so it shows up as
soon as it is saved. Header keys:

- `title` (required), `packageName` (the second line), `description`, `icon` (an emoji or an
  image path relative to the script; a URL is ignored, so no icon is ever downloaded).
- `mode`: `silent` closes the panel and shows the last line of output, if any, in a HUD;
  `compact` keeps the panel open and shows the last line as a toast; `fullOutput` lists the
  output in the panel under the keyword, one row per line, with Copy and Copy All Output
  (a long output is cut to the visible rows; Copy All has all of it); `inline` runs like
  `compact`, since Mestre has no auto-refreshing rows. A missing or unknown mode is `compact`.
  When the panel has closed before a script finishes, its message shows in the HUD instead.
- `argument1`…`argument3`: JSON with `type` (`text`, `password` or `dropdown` with `data`
  `[{"title", "value"}]`), `placeholder`, `optional` and `percentEncoded`. ⇥ on such a script
  (or ↩, when an argument is required) puts `script <title> ` in the field; type the values and
  press ↩. Values are separated by spaces, a quoted phrase is one value, and the last argument
  takes the rest of the line. An empty optional argument is passed as `""`. A `password`
  argument is masked in the chip under the field, but the field itself shows what you type.
- `needsConfirmation`: `true` asks before every run.
- `currentDirectoryPath`: where the script runs; relative paths start at the script's folder.

`script` alone lists every script; `script git` filters them. A non-zero exit shows the last
line of stderr (or of stdout) as the error; a run past `timeoutSeconds` is stopped. Actions:
Run, Show in Finder (⌘↩) and Edit Script. Mestre never logs what a script prints.

## Themes

A theme is one JSON file: the same panel for every theme, with only colours, type, corners and a few
sizes changing. It cannot add information, run code or start a timer. The built-ins are in
`Sources/MestreCore/Resources/theme-*.json`. Settings › Appearance › Customise This Theme copies the
current theme to your themes folder and opens the copy, which you can then edit. To add your own, or
replace a built-in, save `~/.config/mestre/themes/<name>.json`; it appears with the others in
Settings, or set `panel.theme` to `<name>`. It applies when you save.

Every key is optional. Sizes are in points; colours are anything `panel.accentColor` takes.

```json
{
  "material": "none",
  "cornerRadius": 26, "rowRadius": 10, "iconRadius": 14, "tileRadius": 16,
  "borderWidth": 1.5, "fieldHeight": 56, "queryFontSize": 22,
  "labelCase": "lower",
  "fonts": { "ui": "system", "query": "monospaced", "queryWeight": "light" },
  "light": {
    "panel": "#e9e8e3", "border": "#00000020", "ink": "#2a2a28", "inkSecondary": "#62615a", "divider": "#00000014",
    "accent": "#e2531a", "running": "#c9440f",
    "selection": "#f8f7f3", "selectionInk": "#2a2a28", "selectionSecondary": "#62615a",
    "iconTile": "#dcdbd4", "iconSymbol": "#3f3e39", "selectedIconTile": "#232422", "selectedIconSymbol": "#f1f2ea",
    "keyCap": "#f8f7f3", "keyCapInk": "#2a2a28", "keyCapEdge": "#00000026", "selectedKeyInk": "#1b1920", "primaryKey": "#e2531a", "primaryKeyInk": "#ffffff",
    "field": "#232422", "fieldInk": "#f1f2ea", "fieldSecondary": "#a3a697", "caret": "#e2531a",
    "footer": "#262725", "footerInk": "#f0efe9", "footerSecondary": "#c9c8c1",
    "kinds": { "app": "#b3afef", "file": "#5fd36a" },
    "tiles": ["#1c1c1e", "#ffd60a", "#2f6fe8"]
  },
  "dark": { "panel": "#232422", "ink": "#efeee8", "inkSecondary": "#a9a89f" }
}
```

- `light` and `dark` are the theme's palettes, one drawn according to `panel.appearance`. Each takes
  the same keys and neither inherits from the other. With only one of them the theme stays in that
  mode. A file can instead have a single `colors` palette, plus `"appearance": "light"` or `"dark"`
  to say which mode it is.
- `fonts.ui` and `fonts.query` are `system`, `rounded`, `monospaced`, `serif` or an installed family
  name; a family that isn't installed falls back to `system`. `queryWeight` is `light`, `regular`,
  `medium`, `semibold`, `bold` or `heavy`.
- `labelCase` (`upper`, `lower`, `none`) applies to section headers and kind labels.
- `field` and `footer` turn the search field and the footer into filled bars inset in the panel, with
  corners that follow `cornerRadius`.
- `selectedKeyInk` is the ink and edge of a key cap on the selected row, for caps with no fill.
- `kinds` colours section headers and symbols by item kind (`app`, `file`, `command`, `feature`…).
- `tiles` are the fills the tile home screen cycles through, with black or white text, whichever
  reads.
- A painted `panel` turns the blur off unless `material` says otherwise. A colour that doesn't parse
  keeps the default look for that key; a file that doesn't parse uses the default look, and
  Settings › Appearance says why.

