# Standalone Hello Lock — technical preview

Settings and visual previews run without Omarchy. An experimental standalone
locker now implements real Wayland session locking and password authentication
on Hyprland and Sway. Keep your existing locker until you have validated your
own environment; installing these files does not replace it automatically.

The standalone locker is password-only. Fingerprints, additional-factor PAM
conversations and complete parity with the Omarchy service are not implemented.
No desktop startup entries, keybindings or existing lock services are changed.

## Run from this checkout

Requirements: Python 3, Quickshell with Qt Quick/Effects/Shapes and Wayland
layer-shell support, and the Qt SVG image plugin. The native file chooser uses
QtQuick.Dialogs and your desktop's dialog integration. Image paths can also be
entered directly. Optional sound playback uses pw-play or paplay; typing audio
uses optional Qt Multimedia support. Optional weather uses curl; the bounded
status helper uses the coreutils timeout command. No package installation is
performed by these commands.

```sh
./bin/hello-lock settings
./bin/hello-lock preview
./bin/hello-lock splash
./bin/hello-lock doctor
```

Settings has live previews, wordmark generation, image import, symbols, effects,
sounds and saved brand presets. The full-screen preview buttons use sample
input and never authenticate. Click the lock preview to return to Settings (or
exit when launched directly); unlock previews also return when they finish.
Real locks select branding presets once after compositor confirmation. Cycle and
shuffle history persists separately for each profile, including symbol, effect
and typing-sound shuffle bags. Repeated requests, previews and backend recovery
do not advance the selection. Custom two-part symbols remain intact.

Lock, error and unlock cues use the shared sound helper. Typing sounds use an
optional preloaded player and receive only an edit pulse, never password data.
Sound preferences, mute, quiet hours and the sounds-off marker still apply.
Status includes battery, date/birthday greetings, time away and cached local
pacman update counts when available; other package managers omit that count.

Standalone weather is off until explicitly enabled in Settings. Its location
and units are independent of Omarchy; an empty location lets the weather service
infer location from your IP. Requests use the shared weather helper with a
30-minute cache under `~/.cache/hello-lock-standalone/<profile-hash>/weather.json`
(or `XDG_CACHE_HOME`). Disabling weather prevents subsequent refreshes and omits
cached weather from status. Settings stages use samples and never fetch weather.
Audio, status and rotation are optional components; their failure cannot hold
up authentication or lock release.

The real lock uses the selected logo, typing effect, clock, tint and motion;
the unlock uses symbols/parts, handoff, greeting, backdrop and duration.
Screenshot/CRT capture is best-effort and parallel to locking. It uses grim,
private runtime directories and numeric filenames, with per-output completion,
a three-second expiry and generation checks. Capture failure skips the effect.
Automatic motion follows Hyprland's animation setting; Sway uses calm motion.
Explicit Full and Calm override that choice. Query failures prefer calm motion.
The setup-again link and Omarchy menu controls are hidden.

Preferences default to `~/.config/hello-lock-standalone/`. They use the same
atomic persistence helper and asset importer as the plugin, with a separate
profile. The existing `~/.config/hello-lock/` settings remain separate.

```sh
./bin/hello-lock settings --config-dir /absolute/path/to/a/test-profile
```

The built-in standalone logo is Hello Lock's prompt symbol. The Omarchy symbol
and wordmark style remain available among the shared assets.

## Idle and suspend integration

Run `hello-lock idle` inside the graphical session to lock after five minutes,
on logind Lock requests and before logind-controlled sleep. `--idle-seconds N`
changes the timeout. It requires swayidle with systemd/logind support and refuses
another swayidle/hypridle daemon. It ignores swayidle's existing config, never
installs an unlock hook, and stopping it does not stop an active locker.

The before-sleep command returns only after compositor confirmation. swayidle's
`-w` keeps its logind delay inhibitor until that command returns, subject to
logind's finite InhibitDelayMaxSec. It cannot promise protection if lock startup
fails or exceeds that limit, nor for sleep paths bypassing logind. The explicit
`hello-lock suspend` command refuses to request suspend unless locking succeeds
and still reports secure. See the [swayidle manual](https://github.com/swaywm/swayidle/blob/master/swayidle.1.scd)
and [logind inhibitor contract](https://systemd.io/INHIBITOR_LOCKS/).

Nothing is activated automatically. See [packaging and optional user-unit setup](packaging.md)
for installation, activation and removal. A directly launched compositor can
start `hello-lock idle` from its own session startup instead of a systemd unit.
Keep one idle owner; merge the lock command into your existing policy if needed.

## Appearance

The initial standalone palette is supplied locally. Optionally create
`appearance.json` in the standalone preferences directory:

```json
{
  "background": "#1a1b26",
  "foreground": "#c0caf5",
  "accent": "#7aa2f7",
  "urgent": "#f7768e",
  "wallpaper": "/absolute/path/to/wallpaper.jpg"
}
```

Colors accept six-digit hex values; absent/invalid values use defaults.
Appearance and settings reload in Settings/previews; a real lock snapshots them
at startup. The wallpaper applies to
full-screen visual previews; Settings stages use their own illustrative desktop.
Appearance is currently file-configured, with a graphical editor deferred.

## Experimental password locking

The locker needs a normal desktop user, a working Hyprland or Sway session,
Quickshell's Wayland and PAM modules, and the managed root-owned PAM policy.
The policy contains `auth include login`, following the distribution's login
authentication stack. It never edits the existing `login` policy and refuses to
replace a different `hello-lock` policy. Administrators with MFA or custom
policies must review compatibility; only one hidden password prompt is supported.

User installation and PAM installation are separate, explicit operations:

```sh
./bin/hello-lock-install install
sudo "$HOME/.local/share/hello-lock/bin/hello-lock-pam" install
hello-lock doctor
hello-lock lock
```

The user installer defaults to `~/.local/share/hello-lock` with a command under
`~/.local/bin` (which must be on PATH). It refuses to overwrite unrelated commands
or modified managed files. `--data-dir` and `--bin-dir` select other locations.
It does not install distribution packages.

On Hyprland, automatic recovery after a dead locker requires
`misc.allow_session_lock_restore = true` in the compositor's configuration
(`misc { allow_session_lock_restore = true }` in legacy syntax). The installer
never changes this setting. With restore disabled, a crashed lock stays held
but automatic UI recovery can fail. Sway permits replacement of abandoned locks.
The launcher refuses a second live Hello Lock instance and checks Hyprland for
an existing compositor lock before its initial request.

```sh
hello-lock status
hello-lock lock --plain
hello-lock lock --background
```

`--background` returns success only after compositor confirmation; it is a
readiness barrier for future idle/suspend integration. No idle service is
installed. `--plain` uses an independent password field; missing optional QML
visuals also fall back to that field. The security core has no password-submit
or unlock IPC. A fresh PAM success starts the fixed 360 ms release gate;
optional animations cannot hold the lock beyond that gate. The desktop splash
is skippable and bounded. Unexpected backend death leaves the compositor lock
held and triggers bounded recovery with fresh authentication.

Runtime state lives in a private directory beneath an absolute, owned
`XDG_RUNTIME_DIR`, never shared `/tmp`. State records omit password content and
length; child core dumps are disabled. A source snapshot prevents development
edits from automatically reloading an active locker. Status output is diagnostic
state, not independent proof that a compositor is secure.

Remove only the managed files, preserving preferences and modified files:

```sh
sudo "$HOME/.local/share/hello-lock/bin/hello-lock-pam" remove
./bin/hello-lock-install remove
```

Do not remove the program or its PAM policy during an active lock. PAM removal
refuses a policy that differs from the managed template.

## Shared architecture

- `platform/Color.qml`, `Style.qml`, `Util.qml`: small shared visual interfaces,
  independent of Omarchy and compositor modules.
- `Service.qml`: Omarchy host, supplying its live Commons palette and font
  tokens. Its authentication and 360 ms release gate are retained.
- `adapters/omarchy/FocusedMonitor.qml`: optional focused-screen adapter.
- `standalone/shell.qml`: visual host; does not import the service or PAM.
- `standalone/lock.qml`: independent session-lock/PAM core and plain fallback.
- `standalone/runtime.py`: private runtime ownership, source snapshots, readiness
  and bounded backend recovery.
- `bin/hello-lock`: stages only shared visuals in a temporary launch root,
  as Quickshell resolves its imports within that root. The staging folder is
  removed on normal exit. Persistent preferences live outside it.

The launcher gives helpers `HELLO_LOCK_CONFIG_DIR` for the selected profile.
Other uses of the helpers retain their existing XDG defaults when it is absent.

## Verification and remaining work

```sh
python3 -m unittest discover -s tests -v
node tests/test_service.js
node tests/test_standalone_lock.js
python3 tests/run-standalone.py
python3 tests/run-settings-close.py
```

The standalone runtime check requires Wayland. It stages neither Omarchy's
Commons/Ui modules nor Service.qml and uses disposable config/cache/state.
It checks all eight sections, saving/generated wordmarks, imported logos,
appearance, dialog compilation, previews and return to settings. It does not
click a native file chooser or exercise PAM. The runtime check also passed on
this Hyprland laptop in a bubblewrap filesystem namespace with
`/usr/share/omarchy` hidden and `hyprctl`/`omarchy-file-select` replaced by a
failing executable. A subsequent autonomous run on a clean official Arch VM installed Hyprland and
Quickshell without Omarchy and passed this same visual suite. Fedora 44 then
passed with native Sway and Quickshell packages, including an inspected Settings
frame. A genuine CachyOS installation then booted independently with its CachyOS
kernel and passed on Hyprland; its exported Settings frame was inspected too.
Other compositor and distribution combinations still need validation.

The tested runtime reports an existing LogoImage aspect binding warning in the
Unlock stage, plus portal/accessibility warnings from this desktop environment.
The rendered Settings window was inspected; no QML errors were reported.

The expanded standalone suite exercises installed native packages, real
wrong/correct PAM passwords, compositor confirmation, desktop pixel/input
witnesses, backend recovery, rapid relocks, missing optional components,
rotation, capture/cleanup, motion, idle/logind hooks and kernel-confirmed s2idle.
Hyprland guests additionally exercise mixed-scale virtual outputs. The optional
systemd unit has a separate check that stopping idle leaves an active locker
protected and usable with real PAM.

Tests run in disposable Arch/Hyprland, Fedora 44/Sway and genuine
CachyOS/Hyprland guests without Omarchy, using generated credentials through
QMP keyboard input. The selected QXL/Mesa fixture uses Sway's pixman renderer
on Fedora; default Sway rendering intermittently failed the display witness or
recovery startup. Passing the selected configuration does not establish the
cause of every earlier failure. The default virtio GPU fails sleep/display
recovery in this lab; inactive placeholder frames are never accepted.

Forecast/audio transports are guest fixtures. Live weather, physical audio,
fingerprints, monitor hotplug, deep S3 and owner-machine authentication remain
unverified. Debian/Ubuntu runtime support is not established by the .deb builder.
Compositor-forced lock loss can expose a gap before userspace recovery; this
preview is not proof of uninterrupted protection or an independent audit.

See [autonomous testing](autonomous-testing.md#verified-here) for the current
per-distribution results, [release review](release-review.md) for findings and
limitations, and [packaging](packaging.md) for the private preview workflow.

The [autonomous VM lab](autonomous-testing.md) prepares independent guest test
accounts and virtual input/screen control for unattended testing. See its current
verification status and remaining work before interpreting VM results.
