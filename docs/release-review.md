# Standalone release review

Review date: 2026-11-02 (Pacific). Candidate: local `0.5.3-0.preview1` packages.
This is an internal engineering review, not an independent security audit or a
published release. No owner desktop configuration, live PAM policy or running
plugin was changed. This review did not include a commit, push, tag or marketplace submission.

## Scope

Reviewed the standalone session-lock/PAM core and supervisor; optional branding,
audio, weather, motion and capture; idle/logind integration; user installation
and native package construction. Native packages exclude Omarchy Service.qml,
test harnesses, private guides, Git data and user preferences. Existing Omarchy
service work in this checkout is separate from this standalone candidate.

## Findings addressed

- **Unexpected native lock loss:** the standalone host now detects both a lock
  drop and a secure-only drop. It clears pending input/grants and stops the old
  authentication context before bounded recovery with fresh PAM. Parent recovery
  also recognizes a short-lived confirmed state. Intentional release has its
  own internal guard. This addresses the missing detection described in
  [issue #2](https://github.com/denonmaryland/hello-lock/issues/2), but cannot
  promise uninterrupted protection if the compositor itself releases its lock.
- **Relock during an unlock decoration:** a generation-tagged cosmetic finish
  request can shorten an overlay only after authenticated release. Ownership is
  relinquished after the backend exits, before optional cleanup. Capture metadata
  is generation-specific so old cleanup cannot overwrite the new lock's files.

- **Package installation permissions:** omitted directory entries let a
  restrictive installer umask make root-owned application directories
  unreadable. Package archives now explicitly carry 0755 directories and
  normalized file modes. The Arch failure was reproduced as PermissionError;
  installed-package real PAM tests passed after the fix.
- **Idle service lifetime:** the optional user unit uses `KillMode=process` so
  stopping the idle policy does not kill its independently supervised active
  locker. A disposable systemd user-manager test checks lock confirmation,
  blocked desktop input and real PAM after stopping the unit.
- **Threaded process launch:** capture introduced a worker thread before the
  backend launch. Removed Python preexec_fn from that launch; core dumps are
  disabled on the supervisor before children/threads start and inherited by
  children. This avoids running a Python fork hook in a threaded process.
- **Optional work isolation:** motion loads separately from the security core.
  Capture profile reads are bounded, reject symlinks/nonregular files and run
  off the acquisition path. Capture failures, late results, missing components
  and expiries do not control authentication or release.
- **Capture privacy:** owned private runtime, 0700 capture directories, 0600
  numeric files, structured grim arguments, generation checks, per-screen
  acknowledgments and a three-second lifetime. Crash/release paths clean late
  results; startup also recovers stale captures through the shared helper.
- **Source boundary:** native/user builders refuse symlink source roots and
  exclude private guides/cache files. Native packages declare their dependencies,
  preserve PAM configuration through package-manager metadata, and do not enable
  services or modify another locker's configuration.
- **Bundled notices:** Delta Corps Priest 1 matches the pinned figlet.js source
  byte-for-byte. Added its upstream MIT notice and revision/hash record. SIL OFL
  notices remain with the two bundled UI fonts. Package metadata identifies MIT
  and OFL-1.1 and carries complete notices.

## Authentication and integration assessment

PAM success remains the only release authority; no password-submit/unlock IPC
was added. The native PAM user derives from the process UID. Echo-on and
additional-factor prompts are refused instead of receiving a password replay.
Input is absent from state, diagnostics and audio interfaces. Optional visuals
cannot hold the enabled animation path past its 360 ms gate. Explicit instant
mode releases directly after real PAM success. Abandoned compositor locks
require fresh authentication after recovery.

Idle uses a single owned swayidle process, literal quoted command arguments and
compositor-confirmed background readiness. Explicit suspend rechecks the locked
phase as well as the secure flag, rejecting stale lock-loss state. Idle installs
no unlock event. A
before-sleep delay inhibitor is finite; failure or excessive startup latency can
outlast logind's delay. The explicit suspend command aborts before requesting
sleep when readiness fails. Graphical-session environment setup and one idle
owner remain installation requirements.

## Verification record

Final private candidate runtime payload SHA-256:
`df0aea3ac37bbf4ee913579859851421872c01522f5c06a24f956d04293032a4`. The digest covers code, assets, installed unit and PAM policy;
package documentation has separate per-file manifest hashes.

| Guest | Quickshell | RAM | Checks | Recorded UTC |
| --- | --- | --- | --- | --- |
| arch / Hyprland | 0.3.2 | 1024 MiB | 34 passed | 2026-11-03T07:49:31.175698+00:00 |
| fedora / Sway | 0.2.1 | 1024 MiB | 32 passed | 2026-11-03T07:54:06.583113+00:00 |
| cachyos / Hyprland | 0.3.2 | 1024 MiB | 34 passed | 2026-11-03T07:45:47.458740+00:00 |

All three use QXL/Mesa; Fedora uses Sway pixman. Each passed native package
install/remove and real PAM, recovery, capture cleanup, idle/logind, two kernel
s2idle counter increments and idle-unit stop survival. Each is a disposable
guest without Omarchy, using generated credentials only through QMP. Local
validation passed 128 Python tests, both Node suites, six offscreen real QML
motion cases, plugin validation and diff whitespace checks.

The local Python/JavaScript suites and plugin validation are recorded alongside
the final candidate artifacts. Native VM results are in per-distribution
`result-<distro>-standalone.json`; a matrix entry alone is not verification.
Results include actual checks, distro/kernel identity, package format, source
payload digest, kernel suspend counters and pre-sleep lock confirmation.

Expanded VM checks cover installed native package/PAM behavior and removal,
wrong passwords, confirmed locking, crash recovery, repeated/rapid requests,
s2idle, virtual outputs on Hyprland, optional component failures, rotation,
weather/cue policy, native capture/cleanup, automatic/explicit motion and real
idle/logind hooks. Forecast and audio transports are guest fixtures; PAM,
session locking, keyboard input and sleep use native guest interfaces.

The new logind fixture initially returned before the queued suspend completed;
it now waits for a real kernel counter increase before cleanup. Driver failures
still override earlier partial passes. Safe progress and rejected frames are
retained for diagnosis and never treated as a complete pass.

## Remaining limits

A compositor-forced release can expose a gap before a user-space locker restores
protection. Native detection/recovery is not a compositor fix or proof of
uninterrupted security. A stable release must not claim that guarantee on the
basis of these tests. The known issue and the separate Omarchy 0.5.4 security
release work remain distinct from this standalone preview.


Fedora QXL/Mesa with the default Sway renderer intermittently produced black
frames or a recovery-startup timeout. The lab now selects pixman for Sway's
software compositor while Qt continues rendering normally. Passing runs certify
that selected configuration; they do not prove every cause of the historical
failures fixed or establish physical GPU compatibility.

Deep S3, physical monitor hotplug, fingerprint hardware, live weather delivery
and physical audio output remain unverified. Standalone supports one hidden PAM
password prompt, not arbitrary MFA conversations. Hyprland crash restoration
requires its documented compositor setting. Debian/Ubuntu runtime blockers are
still tracked separately; .deb construction does not establish runtime support.
An independent security review remains appropriate before a stable release.

## Separate review follow-up

A separate AI reviewer found no reproducible new defect within the standalone
scope at the digest above. Its test evidence, scope and limits are recorded in
[the dated review](security-review-2026-11-03.md). This does not substitute for
a human audit or remove the known compositor-loss limitation.
