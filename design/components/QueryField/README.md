# QueryField

An AppKit NSTextField with no border, background or focus ring, set in `query` (20 pt, `panel.queryFontSize`), after a magnifying-glass glyph at 0.8 × that size in `ink-secondary`; the row pads 16 and is 52 pt tall.

- Placeholder: "Search apps, or pick a feature below…" in `ink-tertiary`; when the home screen is off it reads "Search apps…".
- Single line, tail-truncated; keys are intercepted by the panel before the field, except while an input method is composing.
- The caret is the system caret in `ink`. Don't: a clear button, a search icon on the right, a mode chip inside the field. Keywords are typed, not selected.
