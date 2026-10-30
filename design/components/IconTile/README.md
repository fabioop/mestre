# IconTile

The 28 pt leading slot of a row (`panel.iconSize`). An NSImage (app, Finder, swatch, emoji) is shown as-is; otherwise an SF Symbol at half the icon size, medium, sits on a tile whose radius is a quarter of the icon (`radius-tile`).

- Unselected: tile `tile`, symbol `ink-secondary`. Selected: tile `selection-tile`, symbol `accent-symbol`.
- Fallback symbol is `circle.dashed`. Colour swatches are 32 pt at `radius-action`, inset 2, with a `hairline` stroke.
- Don't: tint app icons, draw a tile behind an image, use multicolour symbols.
