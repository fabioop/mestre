# Panel

The one surface: a borderless, non-activating floating NSPanel, 720 pt wide, that holds the query row, a hairline, the list and the footer. Use it as the frame for every panel preview.

- Background is the material (`panel.material`, default glass); corners `radius-panel`, continuous; the system shadow only.
- Height is content: `field-height` idle, then + 1 + rows × `row-height` + 16 + headers × 24 + 1 + `footer-height`, capped at `max-rows`. The top edge stays put while it grows.
- Centred on the screen under the mouse, top at `panel.verticalPosition` (0.22) of the visible frame.
- Closes when it loses key status or on ⎋. Draggable by its background.
- Do: keep the idle panel to the query row when the home screen is off. Don't: add a toolbar, a status line, a sidebar; the footer is the only chrome.
