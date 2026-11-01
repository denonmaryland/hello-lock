# Changelog

## Unreleased

- Settings previews follow Hyprland's disabled animations in Automatic motion mode, while Full and Calm override the desktop preference immediately. The isolated preview also uses a disposable weather-cache path.
- Settings has a new "Studio" layout: an icon rail of eight sections, the section's settings, and a live preview stage beside them that shows what they change. You types the greeting as you edit your name and status word (with a birthday preview); Logo shows your logo on a miniature lock screen and switches an image between theme and original colours; Unlock replays a short reveal and plays the chosen logo-to-symbol transition in place with the real transition file, follows Greeting and Background, and keeps a full-screen button for the real preview; Typing runs the real typing effect on your logo with pretend keystrokes (Type, Clear, a key scrubber); Lock screen plays the CRT power-down as a storyboard and shows the clock and Caps Lock badge; Sound puts every cue on one desk with waveforms precomputed by the new `sounds/peaks.py`, playheads, the Coin cue's hit markers and a level meter (each Play runs the sound helper once); Presets shows saved looks as a carousel; Weather outlines where the weather appears and states what leaves the machine. Colours come from the Omarchy theme (light themes included), reduced motion keeps fades only, idle previews stop, and the window scales down on smaller screens. Saving, presets, the menu entry and close behaviour are unchanged.
- Two new Settings → Unlock options. **Greeting** (`greeting`) turns off the status line, greeting and weather/battery text, so the unlock is just the symbol (it settles, holds a beat and leaves, a little sooner than with text). **Background** (`unlockBackdrop`), when turned off, fades the blurred backdrop away right after you unlock, so the symbol animates over your live desktop and open windows; a soft dark halo behind the symbol keeps it readable on bright windows. Both default to on, apply to every unlock animation and to reduced motion, and leave the release gate and the lock-to-splash handoff frame unchanged.
- Every animation was refined against Raphael Salaja's motion guidelines: things arriving ease out, things leaving ease in, no linear motion, subtle squash and stretch, short staggers, and one focal point at a time. Shared timings keep similar elements consistent. Unlock animations now land exactly on their sound hits; this fixes Heartbeat's late second ring, and the Coin sound gains a soft pulse on its ring. Greetings wait until the last hit, and the text leaves before the symbol. The 15 logo handoffs share exit/arrival curves; logo and symbol now overlap rather than cut, and flip turns in one continuous motion. Typing effects respond within about 200 ms without queuing, submit fills in about 250 ms, and failures are shorter and gentler, with no strobing. The lock screen gets a damped-sine shake, a smoother glitch decay, a clock crossfade, a tighter CRT power-down and a calmer "Checking…" state. Setup and Settings have exit animations, press states and quicker step changes. Reduced motion stays fades only, now including setup's step shift and the Settings card. The release gate and the frame-identical handoff are unchanged.
- Lock, unlock and wrong-password sounds were redone in the same restrained synth style as the typing pack: dark FM pulses, sub weight and short dry tails instead of mallet chimes. Every cue keeps its timing against its animation; the legendary unlock no longer plays a rising fanfare, and the wrong-password cue is a soft low fall. The new standard-library generator `sounds/generate-cues.py` replaces the ffmpeg `generate.sh`.
- Low-register synth typing sounds: six restrained electronic patches with three variations each, shuffled once per real lock with no immediate repeat. Settings → Sound can pin a patch or turn typing audio off. Optional, preloaded Qt Multimedia playback is bounded and independent of authentication; it receives edit pulses only, never password content, and does not spawn a process per key. Existing volume, mute, quiet hours and `sounds-off` apply; reduced motion silences typing feedback. Added reproducible local synthesis and an isolated audio preview. Choices saved with earlier development names map to the revised patches.

## 0.5.3

- Omarchy menu backups made by 0.5.0 and earlier, which could be readable by other local users, are now made private (0600) as soon as Hello Lock loads, without waiting for a menu change. 0.5.1 only fixed them on the next actual edit, so an already-enabled menu entry kept a readable backup even after you opened Settings (found in marketplace review). Every `bin/hello-menu` command, `status` included, now does this first, and the new `bin/hello-menu secure` does only that. As before, only regular files you own are touched, never through a symlink. `hello-lock-doctor` warns about any that are still readable.

## 0.5.2

- The CRT power-down no longer disappears when `$XDG_RUNTIME_DIR` is traverse-only for your group (mode 710 or 711, as some setups leave `/run/user/<uid>`). `bin/hello-snapshot` used to require exactly 700 and silently skipped the effect otherwise. It now refuses only a runtime directory that other users can read or write; each capture still goes in its own mode-700 directory with mode-600 files. `hello-lock-doctor` warns on the same condition.

## 0.5.1

- `bin/hello-menu` backups of `~/.config/omarchy/extensions/omarchy-menu.jsonc` are private (0600) from the moment they're created. Before, they took the umask's mode, so a private menu could get a backup other local users could read (found in marketplace review). New backups never overwrite an existing file or follow a symlink, older Hello Lock backups are made private on the next change, and a failed write leaves the menu as it was with no temporary file behind.

## 0.5.0

- The unlock no longer cuts from the lock screen to the splash. Your logo stays put while the lock releases, and the splash opens on an identical copy of it. Then it hands over to the symbol in one of fifteen transitions (fall back, lift off, slide, flip, dissolve, split, blinds, scatter, wipe, glitch out, power off, fly through, fold in, drop, pixelate). They're shuffled by default; Settings → Unlock → **Transition** pins one (`handoff`). Other screens and reduced motion get a crossfade.
- **Shuffle** in Settings → Unlock (`"symbol": "@shuffle"`): a different built-in symbol every unlock, each one before any repeats, while your lock-screen logo stays the same. Works inside brand presets too.
- Preview harness: `unlocking`, `logo`, `fullscreen`, `prime` and `handoff` commands to check the handoff frame and each transition.

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
