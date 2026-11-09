# Changelog

## 0.6.6 — 2026-11-09

Hardens the 0.6.4 fix for #2 (lock loss) against the two gaps 0.6.4 left
open. The remaining, narrower windows are listed under Known gaps below.

- While the session lock is missing, Hyprland is put in a dedicated submap
  whose only bind is a catchall no-op. No keybinding runs and no key reaches
  any app, whatever has focus, including an overlay that maps during the loss.
  The 0.6.4 cover inhibited shortcuts only while it had the keyboard. VT
  switching (Ctrl+Alt+F-keys) is handled by Hyprland before keybindings, so a
  console stays reachable. The barrier stays up until the lock has held for
  5 s, so a lock that drops and returns repeatedly leaves no gap. Then it lifts,
  so locked binds such as the lid switch and media keys work on the lock screen
  again. It also lifts on authenticated unlock and when the shell starts, so a
  crashed shell cannot leave it on. If Hyprland does not confirm it, the
  one-second lock guard tries again. To clear it by hand from a console:
  `hyprctl dispatch 'hl.dsp.submap("reset")'`.
- The no-fade rule for the cover is applied again after a Hyprland config
  reload, on each lock loss and on screen changes, as well as at startup and on
  each lock request. Before, a reload during a lock could make a newly mapped
  cover fade in.
- The barrier also holds against an app that requests its own
  shortcut inhibition (the catchall is `dont_inhibit`, but never runs under
  the real lock, where typing goes to the password field).
- Removing the barrier is confirmed, not assumed. If Hyprland refuses or does
  not answer, Hello Lock keeps retrying every second (after an unlock, at
  startup, with or without a lock) instead of leaving every key swallowed on
  the unlocked desktop.
- A cover waits for Hyprland to confirm the no-fade rule before it first
  appears. Only a confirmation from a run started after the last config reload
  counts. A cover that is already shown is never hidden for this.
- `omarchy-shell lock status` adds `barrier` and `barrierState`.
- No change to the password, fingerprint or PAM code.

### Known gaps

The barrier reacts to a loss rather than being in place for the whole lock,
so locked binds (volume, brightness, media, the power key and the lid switch)
keep working on the lock screen. That leaves two short windows without it:

- From the moment the compositor drops the lock until Hello Lock's barrier
  command reaches Hyprland. The cover's shortcut inhibition covers this only
  if the cover already has the keyboard.
- From a Hyprland config reload during a loss until Hello Lock rebuilds the
  barrier's catchall after the reload event.

Both are expected to last milliseconds, but they were not measured.

- If Hyprland never confirms the no-fade rule (for example, `hyprctl eval` is
  unavailable), a cover appears anyway after 300 ms and may fade in instead of
  appearing fully opaque at once. This is deliberate: the other choice is a
  cover that never appears, which would leave the desktop exposed for the
  whole loss.

## 0.6.5 — 2026-11-09

Fixes a Medium finding from the Omarchy plugin marketplace review of 0.6.3
(omacom/omarchy-plugin-marketplace#14051).

- The Settings lock preview's lock view is now created only while the preview
  is shown. Before, it was created at startup and kept while hidden, and its
  password field was disabled but still writable. Qt reads clipboard offers
  into any writable text field, even without focus, so another app's large or
  endless clipboard offer could exhaust the shell's memory or block it.
- A lock view's password field is read-only whenever it does not accept input
  (both previews, and the unlock transition), not only while a password is
  being checked.
- `omarchy-shell lock status` adds `previewLoaded`.
- No change to the password, fingerprint, PAM or lock-session code.

### Still open from 0.6.4 (#2)

The 0.6.4 known gaps remain. One is larger than 0.6.4's notes say: in VM
testing, the cover sometimes took more than 5 s, not 0.2–0.3 s, to take the
keyboard back from another overlay with exclusive keyboard focus. That may be
test-VM slowness, but treat the gap as open-ended until it is replaced. 0.6.6
is planned to replace this keyboard reclaim with a continuous compositor
barrier.

## 0.6.4 — 2026-11-09

Security follow-up to #2 (lock loss treated as an unlock). Thanks to
@mendumohanpramodh-debug for the report.

- A lock attempt that Quickshell cannot complete is retried instead of being
  forgotten. Quickshell 0.3.2 abandons such an attempt without
  `lockStateChanged` or `secureStateChanged`, which left the request latched
  over an unlocked desktop (`omarchy-shell lock status` still said
  `locked: true`) with nothing left to retry it. The first lock had the same gap.
- A one-second guard re-runs lock-loss recovery for the whole lock request, so
  a loss that arrives with no notification at all is still recovered.
- Fail closed while recovering: from the first secure moment of a lock until an
  authenticated unlock, an opaque overlay cover with exclusive keyboard focus
  sits on every screen behind the session lock. A lost lock now shows the cover
  and keeps keystrokes away from desktop apps until the lock is reacquired,
  instead of exposing the desktop for the relock window. PAM success hides it
  with the existing unlock gate; the first lock's power-down is unchanged.
- The cover is now an input barrier against the compositor too. Without the
  session lock, Hyprland still runs its keybindings (an exclusive layer only
  owns the keyboard), so SUPER+SPACE or an exec binding still worked during a
  loss. The cover now holds a keyboard-shortcuts-inhibit request, which
  Hyprland honours for its focused surface, and takes the keyboard back within
  a few hundred milliseconds if another exclusive layer gets it. TTY switching
  is handled by Hyprland outside its keybindings, so Ctrl+Alt+F-keys still
  reach a console for recovery. Bindings marked `dont_inhibit`, or
  `binds:disable_keybind_grabbing`, are not stopped by this.
- The cover maps instantly opaque. Hyprland fades new layers in from alpha 0,
  which could show the desktop through a cover that maps during a loss (a
  refused first attempt, a new output). Hello Lock registers a named
  `no_anim` layer rule for `hello-lock-cover` through `hyprctl eval` at startup
  and on every lock request.
- `omarchy-shell lock status` adds `recovering`, `covered`, `coverKeyboard` and
  `shortcutsInhibited`.
- No change to the password, fingerprint or PAM code.

### Known gaps

0.6.4 is a mitigation for #2, not the complete fix; the issue stays open and
the hardening is planned for 0.6.5.

- If another full-screen overlay with exclusive keyboard focus appears while
  the lock is lost, shortcuts and typing can reach that overlay for about
  0.2–0.3 s before the cover takes the keyboard back.
- Reloading the Hyprland config during a lock drops the no-animation rule
  until the next lock. A cover that first appears after such a reload (for
  example on a newly connected output during a loss) can fade in instead of
  appearing fully opaque at once.

## 0.6.3 — 2026-11-05

- The Caps Lock badge and the failure hint now work on keyboards with no Caps
  Lock LED. Caps Lock is read from `hyprctl devices -j` (the main keyboard,
  else any keyboard that reports it) on the existing 400 ms refresh; the LED is
  still the fallback when hyprctl is unavailable or lists no keyboards. No
  change to the password, fingerprint or PAM code.

## 0.6.2 — 2026-11-05

- Waking from sleep no longer flashes the desktop before the lock screen.
  Locking for suspend (lid closed, sleep from the menu) now skips the
  power-down effect: its desktop capture finished after resume and the effect
  replayed the old desktop over the lock screen. `bin/hello-snapshot` asks
  logind whether the system is preparing for sleep, and the service drops any
  capture that lands more than 2.5 s after the lock started (a suspend
  happened in between). Locking by hand still plays the effect.

## 0.6.1 — 2026-11-05

Omarchy 4.5 compatibility; still works on Omarchy 4.0.6. No change to the
password, fingerprint or PAM code, or to the lock/unlock lifecycle.

- Menu: Omarchy 4.5 renamed the menu's Style section to Appearance, which hid
  Hello Lock's `style.lockscreen` entry. `bin/hello-menu` now reads the section
  from the installed Omarchy's own menu (`$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc`)
  and writes `appearance.lockscreen` or `style.lockscreen` to match (Style when
  that file can't be read, as before). Its own entry under either key counts as
  on. New `hello-menu migrate` renames only the key of Hello Lock's own entry,
  with the usual private backup, when the installed section is known and nobody
  else's entry holds it; the service runs it on load in place of `secure` (which
  it still does first). `remove` takes Hello Lock's entry from either section.
  New `hello-menu section` prints Appearance or Style; Settings and the setup
  use it for their wording. After updating to Omarchy 4.5, expect one automatic
  edit of `~/.config/omarchy/extensions/omarchy-menu.jsonc` when the shell
  loads Hello Lock (backed up first).
- `hello-lock-doctor` reports where the menu entry is and warns when Hello
  Lock's own entry is under a section the installed Omarchy doesn't have.
- Video wallpapers (new in Omarchy 4.5) couldn't be drawn as an image, so the
  lock showed a flat colour. When Omarchy's `shell/plugins/lock/poster.sh`
  exists, the lock, its preview, the unlock splash and the setup now show the
  video's cached still frame from that script, as the stock 4.5 lock does
  (the plain background colour shows until it is ready or if it fails).
  Without the script (Omarchy 4.0) the wallpaper path is used as before.
- README: Appearance → Lock Screen (Style on Omarchy 4.0); the fingerprint flow
  is described as derived from Omarchy 4.0.6 rather than identical to the
  current Omarchy's; supported Omarchy versions noted.

## 0.6.0 — 2026-11-03

- Add explicit standalone idle/logind integration through swayidle, a suspend
  command that aborts unless lock readiness is confirmed, and an opt-in managed
  user-unit helper. Existing idle/compositor configuration is never replaced.
- Wire standalone automatic motion and private, parallel screenshot/CRT capture
  with per-output completion, generation checks, expiry and late cleanup.
- Add local Arch/CachyOS, RPM and Debian package builders, managed PAM config
  metadata, a source manifest and native guest install/remove/PAM checks.

- Wire standalone confirmed-lock preset rotation and persistent shuffle bags,
  optional typing/cue audio and unlock status. Add explicit weather opt-in with
  independent location/units and a profile-specific cache. Keep optional work
  independent of PAM and preserve selections across backend recovery.

- Verify the baseline standalone suite on Arch/Hyprland, Fedora 44/Sway and genuine
  CachyOS/Hyprland in 768 MiB QXL/Mesa guests: real PAM, crash recovery,
  kernel-confirmed s2idle, post-resume screen/input checks and missing-visual
  fallback. Both Hyprland guests also verify mixed-scale virtual-output changes.
  Deep S3 and physical hardware remain unverified.

- Settings → Unlock now offers an animation switch for immediate post-authentication release, plus optional maximum overlay timing with a 0.5–8.0 second slider and exact seconds field (#3). Automatic timing preserves existing animations; the enabled animation path retains its independent 360 ms release gate. Turning animations off skips both that cosmetic delay and the desktop splash, without changing PAM.
- Successful Settings and preset saves explicitly reload the service configuration; closing Settings reloads it again, so applying changes does not depend only on filesystem notifications (#4). Add timing persistence/reopen and missed-file-watch regression checks, and clarify the one-time shell restart after installation or code updates.
- Clarify the font mapping and distinguish the custom MARY logo artwork in example captures from the bundled UI fonts (#1).

- Add an experimental standalone Wayland locker with real PAM password
  authentication, compositor-confirmed background readiness, private runtime
  ownership, source snapshots and bounded crash recovery. Keep a plain password
  fallback independent of optional visuals and a fixed 360 ms authenticated
  release gate. Add explicit user install/remove and separate managed PAM-policy
  tools; never modify existing desktop/idle configuration automatically.
- Add standalone guest authentication tests using QEMU keyboard and independent
  desktop pixel/input witnesses, including wrong passwords and backend recovery.
  Extend the driver for suspend/resume, virtual outputs and missing visuals;
  distinguish implemented tests from verified per-distribution results.

- Add an explicit disposable Arch lock-loss integration suite for the real
  Hello Lock service, Omarchy Commons/Ui modules, Wayland locks and guest PAM.
  Generated credentials reach only the QMP guest keyboard. Cover wrong and
  correct passwords, forced lock loss/recovery, DPMS and virtual-output changes;
  report recovery latency and distinguish guest PAM from physical fingerprints
  and full Omarchy shell/plugin-manager coverage.

- Re-request a session lock lost without authentication instead of clearing the
  lock request and waking the desktop (#2). Recovery handles both lock-state
  and secure-state loss, including secure-only notifications, and preserves
  authenticated unlocks and the fixed visual release gate. Adapted from
  upstream Omarchy PR #14988. This recovers after a loss; it cannot prevent the
  compositor from dropping the lock or eliminate the exposure before recovery.

- Add autonomous distro test profiles for Fedora, Ubuntu, Debian and CachyOS,
  authenticated cloud-image sources, per-distro results and a sequential matrix.
  CachyOS uses a separate guarded installation disk; new profiles remain
  experimental until their full guest tests pass.

- Add a private headless VM lab with verified user-local QEMU tools, generated
  guest credentials, resource gating, cloud-init provisioning and QMP controls.
  A compact 1 GiB guest starts its own Hyprland session and runs the standalone
  visual suite without Omarchy. Add a host memory watchdog and abort cleanup
  regression coverage. Standalone authentication now has a separate explicit suite.

- Add a standalone technical preview for Settings and visual previews, using a
  separate preferences profile and the shared branding/effect components.
- Decouple visual theme tokens and focused-screen selection from Omarchy;
  retain the plugin's live theme through its host adapter.
- Add a native image chooser and path entry for standalone settings, plus
  portability/profile and isolated Wayland runtime checks. Keep visual previews
  independent of the standalone session-lock/PAM core.

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
