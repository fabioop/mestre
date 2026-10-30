# ResultRow

One result: a 28 pt icon, the title with the subtitle inline after it, and the kind label at the trailing edge. 42 pt tall (`panel.rowHeight`), padding 10, gap 10, selection in `selection` at `radius-row`.

- Title `row-title`, one line, keeps its width. A running app gets the 6 pt `running` dot 6 pt after the title with the tooltip "Running".
- Subtitle `subtitle` in `ink-secondary`, 8 pt after the title, truncating first: the match reason and the provider's subtitle joined with " · ". Shown on every row when it is content (expression, keyword, age, hint); metadata (folder, "Browser", a URL) only on the selected row. An alias that matched follows the title as "(ff)" on every row. The role comes from `ItemKind.subtitleRole`, overridable per item; `panel.subtitles: always` shows everything.
- Trailing: the `KindBadge`, on every row. Hints are in the `Footer`, never here.
- Click selects and runs the default action. Don't: wrap the title, colour it with the accent, stack a second line, put a key cap on a row.
