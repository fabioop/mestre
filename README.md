# Mestre

A free, open-source launcher for macOS. Fast, keyboard-first, and configured by one JSON file.

*Mestre* is Portuguese for "master".

## What it does

Press **⌥ Space** and type.

| Feature | Try typing |
| --- | --- |
| Open and switch apps | `saf` |
| Calculator | `2*(3+4)` |
| Clipboard history | `clip` |
| Snippets and text expansion | a snippet's name |
| Emoji and symbols | `:fire` |
| Search files | `file report` |
| Browse folders | `~/Doc` |
| Window layouts | `left half`, or ⌃⌥ ← → ↑ ↓ from anywhere |
| Open windows | a window's title |
| System commands | `sleep`, `lock` |
| System Settings panes | `bluetooth` |
| Quicklinks and web search | `gh swift` |
| Browser bookmarks | `bm swift` |
| Dictionary | `define serendipity` |
| Colour conversion | `#ff8800` |
| Keep awake | `awake 45m` |
| Kill a process | `kill chrome` |
| Apple Shortcuts | a shortcut's name |
| Your own scripts | a keyword you choose |
| Themes | `panel.theme`, or Settings › Appearance |
| Tile home screen | `home.layout`, or Settings › Appearance |
| Automatic updates | `updates.check`, `updates.channel` |

You can also import snippets, quicklinks and hotkeys from Raycast or Alfred under Settings › General.

## Keys

| Key | Action |
| --- | --- |
| ⌥ Space | Open or close the panel |
| ↑ ↓ | Move |
| ↩ | Open |
| ⌘K | All actions for the selected row |
| ⇥ | Enter a feature, or show a row's actions |
| ⎋ | Close |

## Install

Mestre needs macOS 14 or later. Download the latest build from [Releases](https://github.com/fabioop/mestre/releases) and drag it into Applications. Downloads are Apple silicon only.

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
