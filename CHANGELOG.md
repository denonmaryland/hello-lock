# Changelog

## 0.3.2

- `hello-lock-doctor` suggests Omarchy's own `omarchy pkg add` to install a missing tool.
- A preview image for the Omarchy plugin marketplace.

## 0.3.1

- Unlock previews show your current branding; a real unlock keeps the preset that was chosen for that lock.
- A preset save that fails (for example a duplicate name) keeps Settings open on the first close so the error stays visible; closing again or retrying works.
- Malformed preset entries in `config.json` are skipped by Settings and by rotation instead of interrupting your other settings. Preset commands refuse to save until they are fixed.

## 0.3.0

- Brand presets: save your brand text, logo or wordmark, tint and unlock symbol under a name, then use, update, rename or delete them in Settings → Presets.
- On each lock: keep the current branding, cycle through presets in order, or shuffle without an immediate repeat.
- `bin/hello-config preset …` commands for scripting.

## 0.2.0

- Settings window (`omarchy-shell lock settings`): every option on one page, saved as you change it.
- Keyboard focus for buttons and symbol tiles.
- Edits made just before closing are saved; the Custom symbol tile shows both parts of a two-part symbol.

## 0.1.0

- First release: greeting lock screen, eight typing effects, eleven unlock animations and the legendary gold unlock, CRT power-down, setup screen, eleven wordmark styles and forty built-in symbols.
