# HomeScreen

What the panel shows on an empty query when `home.sections` is non-empty: Recent (`home.recentCount`, 5), Features (one row per provider with a hint subtitle and the "Open" action that fills the keyword), Commands (every visible command). Rows are ordinary `ResultRow`s under `SectionHeader`s, with the footer below; `home.hidden` removes any id.

- The Features subtitle is content (it teaches the grammar: "Type 2^10, sqrt(2), 15 % 4, pi*2. Return copies"), so it shows on every row.
- Proposed: hide a feature from Home once its keyword has been typed recently, so the home screen shrinks as the user learns and stays within `max-rows`.
- Don't: tiles, a grid, a greeting, the date.
