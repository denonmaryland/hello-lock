# Changelog

## 0.4.0

- Easier to find the settings again: the setup's last step offers to add **Lock Screen** to the Omarchy menu, under Style (ticked by default; untick to leave the menu alone), and the closing hint points there.
- Settings → Lock screen → **Show in the Omarchy menu** turns that entry on or off.
- New `bin/hello-menu status|add|remove`. It edits only Hello Lock's own line in `~/.config/omarchy/extensions/omarchy-menu.jsonc`, keeps comments and every other entry, backs the file up first, checks the result before writing, and never changes a Style → Lock Screen entry that isn't Hello Lock's.

## 0.3.3

- `hello-lock-doctor` names the package to install for a missing tool instead of printing an install command, so the marketplace's automated scan passes without a manual review.

## 0.3.2

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
