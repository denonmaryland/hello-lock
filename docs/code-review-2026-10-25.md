# Hello Lock review — 2026-10-25

Reviewed the uncommitted project using `code-review-excellence`, covering
correctness, security, maintainability, performance, and test quality. The
review prioritized the lock/authentication boundary, capture lifecycle,
configuration writes, setup, animation fallbacks, and reduced motion.

## Skill comparison

GitHub stars measure repositories, not individual skills. This is a shortlist
of five popular repositories with relevant review skills, ordered by star
count from the GitHub API at review time; it is not an exhaustive global ranking.

| Repository / skill | Stars | Fit |
| --- | ---: | --- |
| [obra/superpowers — requesting-code-review](https://github.com/obra/superpowers/tree/main/skills/requesting-code-review) | 305,133 | Strong independent reviewer workflow; principally delegates a commit-range review. |
| [mattpocock/skills — code-review](https://github.com/mattpocock/skills/tree/main/skills/engineering/code-review) | 303,354 | Standards/spec review; assumes a fixed Git reference and issue-tracker setup. |
| [affaan-m/ECC — security-review](https://github.com/affaan-m/ECC/tree/main/skills/security-review) | 288,944 | Detailed security checklist; much of it concerns web APIs, databases, and tokens. |
| [addyosmani/agent-skills — code-review-and-quality](https://github.com/addyosmani/agent-skills/tree/main/skills/code-review-and-quality) | 110,550 | Thorough multi-axis review and verification, with references to other skills. |
| [wshobson/agents — code-review-excellence](https://github.com/wshobson/agents/tree/0874a27b17a22e2b7c2e2bcd725768e0803cad06/plugins/developer-essentials/skills/code-review-excellence) | 41,715 | Selected: self-contained, language-neutral workflow and Python/security/test checklists fit this QML/Python project without a PR or issue tracker. |

Installed only the selected skill and its two reference documents using the
Codex skill installer, pinned to commit
`0874a27b17a22e2b7c2e2bcd725768e0803cad06`. No third-party scripts or hooks were
needed. The installed instructions and both reference documents were read and
applied during this review.

## Findings and fixes

### P1 — unsafe screenshot fallback and capture lifecycle

Previously `Service.qml` wrote predictable `hello-lock-<output>.jpg` files,
falling back to shared `/tmp` with permissions inherited from the process
umask. This could expose desktop contents to other local users when the
runtime directory was absent. Cleanup raced with an in-flight capture; an
unlock could delete files before the capture recreated them. The first
monitor's finish callback also removed every monitor's snapshot.

Added `bin/hello-snapshot`: a validated private runtime directory, unique
capture directories, private files, numeric filenames, bounded `grim` calls,
and partial-failure cleanup. Service results carry a capture generation so
late results are discarded. Cleanup is queued, all monitors are accounted
for, and a three-second timer covers failed or disappearing views. Old crash
captures are reclaimed after one minute on a subsequent capture.

### P1 — setup changed the saved logo before Save

The wordmark preview rendered straight into `wordmark.svg`. Importing an image
overwrote `logo.<extension>` and removed other logo extensions. Canceling setup
therefore changed or broke an existing logo while retaining the old config.

Wordmark previews now use SVG data URLs produced on stdout. Saving generates
a separate asset and atomically updates the config. Imported images use
content-based names and never remove the previous logo. Stale renderer
results are ignored and Continue waits for the current preview to finish.

### P1 — saving malformed settings silently discarded them

`hello-config save` treated unreadable, malformed, or non-object existing
settings as an empty object, then replaced them. This could discard settings
such as `weather: false` and reset privacy preferences.

Saving now refuses those cases, preserves the original file on failure, makes
a timestamped backup before replacement, writes with mode 600, and removes
temporary files if a write/rename fails.

### P1 — a splash exception could prevent a new lock request

`beginLock()` invoked the optional splash's `finish()` before requesting the
session lock, without an exception guard. A runtime error in that cosmetic
component could interrupt the lock request. That call is now guarded, like
the existing `prime()` and `play()` calls on unlock. The password/PAM routines
were not changed.

### P2 — reduced-motion unlocks still moved

The calm animation scaled the symbol and moved/tracked the greeting; the
forced short preview could also bypass calm mode. Reduced motion now holds
those transforms steady, uses opacity fades, and takes precedence over short
mode. Normal full-motion animations remain available.

### P2 — secondary monitor could end the primary splash early

Every monitor's text timeline called the global `finish()`. A primary monitor
waiting for pixel sampling could have its greeting cut short by another
monitor. The primary now owns normal completion; the explicit secondary-only
preview and global safety timer remain supported. Hiding the splash also
stops each window's animation drivers.

### Supporting changes

- Added helper and service regression suites and an isolated preview launcher.
- Doctor checks the new helper and snapshot locations; its fallback animation
  list includes pixels.
- Added Python-cache/backup ignores and corrected the manifest's animation count.
- Updated the README to describe actual storage, cancellation, and test behavior.

## Verification

- **15 Python tests passed**, including all 11 wordmark styles, malformed-file
  preservation, asset preservation, failed atomic replacement, screenshot
  permissions, unsafe runtime rejection, timeouts, cleanup boundaries, and
  crash leftovers. The former settings/asset behavior failed the corresponding
  regression checks when run against the pre-review source backup.
- **7 JavaScript service scenarios passed**, exercising actual QML function
  bodies with a mock compositor: missing PAM, splash exceptions, the unlock
  gate, failed authentication, multi-output cleanup, URL escaping, and late
  capture completion across unlock/relock. These are logic tests, not proof
  of a real authenticated unlock.
- All production QML files parsed with Qt's `qmlformat`; Python helpers parsed
  successfully. Omarchy plugin validation and the read-only doctor passed.
- The modified `Service.qml` compiled in a real Quickshell process without
  instantiation. The harness instantiated the actual lock view, setup, and
  splash with the installed Omarchy theme modules.
- All eight typing effects ran typing/submit/failure preview sequences in both
  motion modes without QML warnings. Cells, the in-memory LED wordmark, and
  the calm unlock were visually inspected. Setup Save succeeded in the
  disposable config and pointed to its generated SVG.
- A real `grim` capture through the new helper succeeded with directory mode
  700 and JPEG mode 600; cleanup removed it. It was not saved to this repo.
- Password submission, password-prompt response, fingerprint startup and
  completion, authentication reset, and session-lock request functions match
  the installed Omarchy source. No new authentication route was added.

One environment warning appeared when the separate preview process registered
with the desktop portal (an application ID was already associated). The
preview loaded and ran; no component/QML errors followed.

## Remaining limits

- No real lock or PAM exchange was triggered during this review. Authentication
  on the modified service still needs a deliberate manual test after deployment.
- Only one physical monitor was available. Multi-monitor timing and hot-unplug
  handling were reviewed and partly logic-tested, not verified on hardware.
- Existing assets are deliberately retained; repeated image imports can leave
  unused files in the settings directory. They are not removed automatically
  because saved configs and backups may still reference them.
- The older recording script in `typing/harness/run.sh` assumes a specific
  laptop output/geometry. The new preview launcher avoids that recording script.
- Hello Lock still copies Omarchy's lock service; upstream fixes need to be
  compared and incorporated explicitly. This review is not a security certification.
- These changes are in the source project only. The live plugin and user config
  were left unchanged. There was no commit or publication; the install URL still
  needs the chosen GitHub owner before release.

Verdict: the identified P1/P2 defects are addressed in source. The automated
and preview checks pass; live authentication and multi-monitor verification
remain outstanding release checks.
