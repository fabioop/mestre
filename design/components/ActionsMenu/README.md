# ActionsMenu

The ⌘K menu for the selected row: below a second hairline, a block inset 8 with an "Actions" `SectionHeader` and one 30 pt row per action, in provider order. Each row: a 13 pt symbol in a 16 pt column, the title in `action`, a `KeyHint`. Selection in `selection` at `radius-action`. The footer stays below it.

- Order is stable, never by usage. The first action is the default (↩). ↑ ↓ move, ↩ runs, esc or ⌘K closes; changing the row selection closes it.
- Proposed: while open, the list collapses to the selected row so the menu is read as that row's menu, and ⌘1–⌘9 run by number.
- Actions take no parameters here; a command that needs one takes it from the query. Don't: nest, group, add icons the provider did not declare (`circle` is the fallback and should be rare).
