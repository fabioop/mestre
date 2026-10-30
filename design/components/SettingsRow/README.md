# SettingsRow

One row of the grouped Form in the Settings window: a label in `action`, then the field. `NumberField` is 80 pt wide, right-aligned, with its unit in `callout` `ink-secondary` after it; `StringField` is 220 pt; sliders 170 pt. Fields are `field-mono`.

- A row edits exactly one config key and writes on commit. Captions sit under the field: `caption` in `ink-secondary`, errors in `danger` with the fallback stated.
- Behaviours are pickers of named choices, never numeric weights. Every page ends with the config path.
- Don't: a Save button, an Apply sheet, a per-field reset icon.
