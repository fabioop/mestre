# Mestre

![Mestre opens with ⌥ Space and answers as you type, then changes through its themes: mestre, ulm, putty, tiles and micro, in light and dark.](docs/media/mestre.gif)

<sub>The panel in this clip is recreated from the app's theme files, with sample data.</sub>

A free, open-source launcher for macOS. Fast, keyboard-first, and configured by one JSON file.

*Mestre* is Portuguese for "master".

## Principles

- **Fast.** The panel shows in under 50 ms and results follow every keystroke. Mestre uses no CPU while it waits.
- **Configured by one file.** Every behaviour, shortcut and number has a key in `~/.config/mestre/config.json`. The Settings window edits the same file.
- **Private.** Your data stays on your Mac: no account, no analytics, no tracking. Translation and text recognition run on-device, and calendars, reminders and contacts are read through macOS (contacts are kept in memory only). Mestre only goes online to check for updates and to fetch exchange rates (from jsDelivr by default, `calculator.ratesURL`) after you type a currency conversion. Turn them off with `updates.check` and `calculator.currency`.

**Mestre is in beta.** It's ready for daily use, but expect rough edges. Config keys can still change between `0.x` versions, and the release notes say when they do.

## What it does

Press **⌥ Space** and type.

| Feature | Try typing |
| --- | --- |
| Open and switch apps | `saf` |
| Calculator | `2*(3+4)` |
| Unit and currency conversion | `10 km to mi`, `100 usd to eur` |
| Time zones and date maths | `3pm lisbon in sf`, `today + 90d`, `days until christmas` |
| Clipboard history | `clip` |
| Copy text from the screen, and search the text in copied images | `copy text`, `clip invoice` |
| Snippets and text expansion | a snippet's name |
| Emoji and symbols | `:fire` |
| Search files | `file report` |
| Browse folders | `~/Doc` |
| Window layouts | `left half`, or ⌃⌥ ← → ↑ ↓ from anywhere |
| Open windows | a window's title |
| Menu items of the app in front | `menu export` |
| System commands: sleep, lock, volume, Wi-Fi, dark mode, hidden files, quit all apps | `sleep`, `volume 30`, `wifi` |
| System Settings panes | `bluetooth` |
| Quicklinks and web search | `gh swift` |
| Browser bookmarks | `bm swift` |
| Contacts: copy, email, call, message or FaceTime | `contact jane` |
| Dictionary | `define serendipity` |
| Translator (macOS 26) | `tr bom dia` |
| Upcoming events and meetings, from every macOS calendar account | `cal ` |
| Reminders: add one in plain words, tick off what's due | `remind call mum fri 5pm`, `todo ` |
| Colour conversion | `#ff8800` |
| Keep awake | `awake 45m` |
| Kill a process, or whatever listens on a port | `kill chrome`, `kill :3000` |
| Connect Bluetooth devices | `pair airpods` |
| Media controls and what Music or Spotify is playing | `media`, `next` |
| Apple Shortcuts | a shortcut's name |
| Script commands, Raycast-compatible | a script's title, `script ` |
| Themes | `panel.theme`, or Settings › Appearance |
| Tile home screen | `home.layout`, or Settings › Appearance |
| Automatic updates | `updates.check`, `updates.channel` |

You can also import snippets, quicklinks and hotkeys from Raycast or Alfred under Settings › General.
Only web and mail quicklinks come over, and hotkeys only for apps that are installed; the rest are listed for you to add by hand.

## Keys

| Key | Action |
| --- | --- |
| ⌥ Space | Open or close the panel |
| ↑ ↓ | Move |
| ↩ | Open |
| ⌘K | All actions for the selected row |
| ⇥ | Enter a feature or a script's arguments, or show a row's actions |
| esc | Close |

## Install

Mestre needs macOS 14 or later and Apple silicon.

1. Download the latest build from [Releases](https://github.com/fabioop/mestre/releases) and drag it into Applications.
2. Open Mestre. macOS says "Apple could not verify" the app, because builds aren't notarized by Apple yet. Click **Done**, not Move to Trash.
3. Go to System Settings › Privacy & Security, scroll down to Security, and choose **Open Anyway**.

Mestre updates itself after that.

To build from source instead, you need the Command Line Tools (`xcode-select --install`). Xcode is not required.

```bash
git clone https://github.com/fabioop/mestre.git
cd mestre
make install
```

## Configure

Everything lives in `~/.config/mestre/config.json`, and changes apply when you save. The Settings window edits the same file. Every key is optional.

```json
{
  "hotKey": "option+space",
  "hotkeys": { "cmd+shift+v": "feature:clipboard" },
  "aliases": { "ff": "Firefox" }
}
```

See [every option](docs/configuration.md).

## Contributing

Features get added from real use and from requests, so open an issue if something is missing. To work on the code, see [development notes](docs/development.md).

## License

Copyright © 2026 Fabio Pereira. GPL-3.0: you can use, change and sell Mestre, as long as anything you distribute based on it is also GPL-3.0 with its source available. See [LICENSE](LICENSE).
