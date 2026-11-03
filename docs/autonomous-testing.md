# Autonomous test lab

The lab runs disposable Linux guests with their own Wayland desktop and test
account. Arch, Fedora, Ubuntu, Debian and CachyOS have explicit profiles; a
profile is a test target, not a claim of supported or passing behavior. It never needs the owner's password, keyboard/mouse, or presence.
Host locking, suspend, PAM configuration and desktop settings are excluded.
Guest credentials are generated locally and never printed.

## Run

```sh
python3 tests/vm/lab.py check --compact
python3 tests/vm/lab.py prepare
python3 tests/vm/lab.py smoke
python3 tests/vm/lab.py run --distro arch --compact --wait-for-memory 900
python3 tests/vm/lab.py run --distro cachyos --compact --wait-for-memory 900
# Real Hello Lock service, Wayland lock and guest PAM, on Arch only:
python3 tests/vm/lab.py run --distro arch --suite lock-loss --compact --wait-for-memory 120
# Sequential full matrix; continues through blocked/failed/deferred profiles:
python3 tests/vm/lab.py matrix --compact --wait-for-memory 900
```

- `prepare` extracts verified QEMU tools into a private user cache and verifies
  the selected official cloud image. Arch uses its image signature; Fedora and
  Ubuntu use signed checksum manifests and pinned signing fingerprints. It changes no host packages or services.
- `smoke` checks KVM, QMP, virtual input and screenshots in a paused 128 MiB VM;
  it does not boot Linux or prove application behavior.
- `run` boots the guest, installs its dependencies via cloud-init, transfers an
  explicit source bundle, starts Hyprland or Sway and runs the selected suite
  in that actual compositor session (visual by default).

`tests/vm/guest-session.py` configures only the marked disposable guest and
refuses the host. Its guest-only automatic login creates the initial desktop
session; it is not a replacement for lock-screen authentication tests. The
visual suite installs no lock or PAM fixtures. Neither suite installs a PAM
success hook.

`tests/vm/guest-test.py` checks that Omarchy is absent, waits for a real display,
runs the shared suite and records a machine-readable result and sample-data
Settings screenshot. The host retrieves that result, stops QEMU, and removes
the guest overlay, seed, keys, test password and temporary source bundle.
The same temporary-directory cleanup applies when setup or tests fail.

## Lock-loss integration suite

`--suite lock-loss` runs the production `Service.qml` and lock view against a
real guest compositor and PAM. It is separate from standalone locking, which
this suite does not exercise. It transfers only the installed Omarchy Commons/Ui
source modules, with SHA-256 evidence, rather than installing or testing the
full Omarchy shell/plugin manager. It needs those modules on the host and
currently accepts only the disposable Arch profile.

The guarded guest driver installs an `omarchy-lock-password` PAM service that
includes Arch's real `system-auth` stack. The host sends the generated guest
password through QMP virtual keys; it is never sent through IPC/SSH arguments
or included in results. This verifies real password authentication through
Hello Lock, without claiming the host's exact PAM policy was tested. There is
no success hook and no fingerprint device emulation.

The guest-only QML harness can deliberately release its real Wayland lock
without authenticating. Production recovery must retain the request and
reacquire compositor-confirmed secure state. Tests cover wrong-password
rejection, repeated lock requests, authenticated unlocks, three injected losses,
three DPMS cycles and two virtual-output add/remove cycles. It also disables
config file watching and exercises actual Settings saves, instant authenticated
unlock, and restoring animations with a custom time cap. Hyprland's `LOCK`
monitor blocker independently checks protection on all active outputs. Secure
loss-to-recovery timing is recorded; it is an exposure-window proxy, not a
frame-by-frame guarantee of desktop privacy.

The suite does not test physical fingerprint verification, real monitor hotplug,
suspend/resume, the complete Omarchy plugin lifecycle, or standalone locking.
Its fault-injection IPC exists only in `tests/vm/security.qml`; the guest guard
runs before any writes or process launches. Default visual bundles still omit
the service and authentication fixtures. Raw guest logs and credentials stay
inside the disposable run and are removed when QEMU stops.

## Distribution paths

| Guest | Provisioning | Current evidence |
| --- | --- | --- |
| Arch / Hyprland | Signed official cloud image, pacman | Full standalone suite passed with QXL/Mesa in a 768 MiB guest, including s2idle, mixed-scale virtual displays and absent visuals; deep S3 remains unverified |
| Fedora 44 / Sway | Signed official cloud image, native packages | Full standalone suite passed with QXL/Mesa and Sway pixman in a 1 GiB guest, including kernel-confirmed s2idle resume and absent visuals; deep S3 remains unverified |
| Ubuntu 26.04 LTS | Signed official cloud image, apt | VM provisioning completed without required desktop commands; Quickshell is absent from the native package listing |
| Debian 13 | Official cloud image | Blocked before boot: this cloud directory provides unsigned checksums; a signed installer path is needed |
| CachyOS / Hyprland | Signed Arch bootstrap followed by official CachyOS unattended installer on a separate virtual disk | Full standalone suite passed on the installed target with QXL/Mesa in 1 GiB, including s2idle, mixed-scale virtual displays and absent visuals; deep S3 remains unverified |

CachyOS is not reported as an Arch test. The bootstrap receives only a fresh
second virtual disk with serial `HELLO_CACHYOS_TARGET`; the guest installer
refuses any other target, mounted disk or existing filesystem. Package signatures
remain required, with the full official CachyOS signing fingerprint checked
before trusting it. The official installer writes the CachyOS system. The lab
then stops the bootstrap and boots only the installed target. Acceptance requires
`ID=cachyos` and a running CachyOS kernel, as well as the same visual suite.
Generated installer credentials and its logs stay inside the disposable run.
The bootstrap installs CachyOS's signed pacman build and pins CPU-compatible
repositories to reachable official servers, preserving mandatory package
signatures when the installer ranks mirrors. It mounts the automatic Btrfs `@`
root after installation and accepts both tree and flat `lsblk` JSON. Credentials
and installer logs stay 0600; the installer receives a normal system umask so
new system directories have usable permissions. Guest DNS uses QEMU's private
NAT resolver, including inside installer chroots.

The complete compact-mode CachyOS visual run passed. Standalone authentication
was not tested by that visual run.

Cloud provisioning installs dependencies without upgrading the entire guest OS.
Guest identity checks require the requested distro and release. Hyprland before
0.55 receives the legacy config format; newer builds receive Lua configuration.
Fedora uses native Sway; the other configured desktop profiles use Hyprland.
The default visual suite uses no Omarchy packages or live lock service. The
explicit lock-loss suite loads the real service only inside the disposable guest.

## Resource limits

The default VM uses two virtual CPUs and 3 GiB RAM, with a 1.5 GiB host reserve.
`--compact` uses a 1 GiB guest and 768 MiB launch reserve. The guest has a 2 GiB
swap file on its disposable disk; it does not change host swap configuration.
Compact mode passed the actual visual suite on this laptop while the host had
approximately 2 GiB available RAM before launch.

`--tiny` uses a 768 MiB guest, the same 2 GiB guest swap, and a 1 GiB host
launch reserve. It passed the complete QXL/Mesa standalone suite on Arch,
Fedora and genuine CachyOS. The memory/pressure watchdog remains enabled.

All profiles require 20 GiB free disk and accessible KVM. Launch also waits for
memory PSI full avg10 below 2%. A bounded wait retries resources without user
input; if the budget remains unavailable, exit 75 reports
`deferred` before creating credentials or starting a VM. A continuous watchdog
terminates only the test VM after five seconds below 512 MiB available host RAM
or sustained memory PSI full avg10 above 10%. Guest bootstrap and visual tests
also have timeouts. QEMU runs at lower CPU priority. Only one full lab run can
proceed at a time.

The VM is headless and uses a virtual GPU with the host render node
`/dev/dri/renderD128`. It never opens a desktop window or sends host input.
That node is currently specific to the tested laptop; another host needs its
render-node selection and tool preparation validated.

## Private files and results

Everything lives under `$XDG_CACHE_HOME/hello-lock-vm`, defaulting to
`~/.cache/hello-lock-vm`. Directories are private. Each run uses a fresh qcow2
overlay above the verified read-only base. Only the verified base image/tools,
non-sensitive result JSON and sample Settings screenshot remain after the run.
SSH is forwarded on loopback only, uses a generated key and separate known-hosts
file, and disables agent forwarding. Credentials and guest disks do not enter Git.

`settings-<distro>.png` retains each passing guest's sample Settings frame.
`weather-<distro>.png` captures the standalone location/unit controls when the
expanded visual suite exports them. These are disposable sample profiles.

The standalone feature checks also cover confirmed-lock preset selection,
rotation reuse across repeated requests and backend recovery, strict weather
opt-in/cache/opt-out, lock/error/unlock cue dispatch and mute policy, and real PAM
with optional audio/status components absent. Forecast and audio transports use
guest-only fixtures: these checks establish dispatch and policy behavior, not
live forecast delivery or audible output. PAM still uses the guest's native
stack and generated credentials through QMP.
`result-<distro>.json` and `last-result.json` record status, timestamps and distro
identity. Visual runs record their suite exit code and
`authentication_tested: false`. Lock-loss runs record real password coverage,
individual checks and recovery timings. Provisioning alone is never a passed
application test. Failed, blocked and deferred runs replace the corresponding result with an explicit
summary. `matrix-result.json` collects the results of one sequential matrix run.
Provisioning checks fail promptly if Hyprland or Quickshell is missing. A blocked
setup is separate from a failed application test; no visual pass is inferred.
A competing lab invocation reports `deferred` rather than starting another guest.
The default visual source bundle excludes Service.qml and the Omarchy adapter.
Both suites exclude private guides, hidden files, symlinks and local repository
state. The explicit lock-loss bundle adds the production service, its adapter
and guarded guest-only security fixtures.

Rootless tool preparation currently targets this Arch-family host and its
existing pacman databases. Other host distributions need their own tool adapter.

## Verified here

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

The latest private candidate extends earlier 20/21-check feature runs with
native package install/remove and payload validation, automatic motion, real
CRT capture/cleanup, rapid relocks during unlock decoration, actual swayidle
and logind lock/before-sleep events, and systemd user-unit lifetime testing.
Native PAM, keyboard input, compositor locks and kernel s2idle are real guest
interfaces; forecast/audio transports are fixtures. Weather controls and
fallback frames were visually inspected. Per-candidate validation JSON records
carry the exact source-payload digest and individual assertions.

Fedora uses pixman for Sway with the QXL software fixture; Qt still uses Mesa.
Earlier default-renderer runs intermittently failed the pixel witness or
recovery startup. Selected-renderer passes do not root-cause every prior failure
or establish physical GPU compatibility. Rejected frames remain diagnostics,
never partial support evidence. The final candidate matrix is also recorded in
[release review](release-review.md).

2026-11-02 (recorded `2026-11-03T00:58:07.669426+00:00` UTC): the working tree's unlock
controls and explicit Settings reload passed an expanded **32-assertion** real
service/PAM run on disposable Arch/Hyprland. The harness disabled the service's
config file watcher, saved through the actual Settings component, and observed
the new values without a shell restart. Instant mode rejected a wrong password
and released only after real PAM success, without entering the visual gate or
showing a splash. Re-enabling animations restored the gate; a 600 ms cap ended
the real post-release overlay. Existing loss recovery, DPMS and virtual-output
checks also passed. Injected-loss recovery was 570, 577, 564 ms; the remaining exposure
window is unchanged in kind. Generated credentials reached only QMP keys. The
run used guest system-auth, without a fingerprint device or the full Omarchy
shell/plugin manager. The guest and its private run files were cleaned up.

Tested Service.qml SHA-256:
`50f8e901af19285ce46c2fe79379e16fa970c46e631258928b31ff7f2e5a82fd`.
This is working-tree feature evidence, separate from the isolated 0.5.4 security
release candidate. The guarded `qa.saveTiming` fixture lives only in the guest
test harness; it does not add production IPC or an authentication-success hook.


2026-11-02: the first real lock-loss integration run passed on disposable Arch
(kernel `7.2.11-arch1-1`, Hyprland `0.57.0`, Quickshell `0.3.2`) with the
production service and installed Omarchy Commons/Ui sources. It passed 23
assertions: wrong-password rejection, five authenticated unlocks via QMP/PAM,
repeated lock requests, three real lock releases and recovery without further
authentication, three DPMS cycles and two virtual-output add/remove cycles.
Hyprland confirmed the `LOCK` blocker on every active output. Secure-state
recovery took **539, 536 and 530 ms** after the injected losses. No incidental
lock losses occurred during the DPMS/output cycles. These timings demonstrate
a remaining exposure window; they do not establish uninterrupted lock coverage.
The guest used Arch `system-auth` under the production PAM service name, not the
host's exact PAM stack. Physical fingerprints and the full Omarchy shell/plugin
manager were not exercised.

Evidence: `$XDG_CACHE_HOME/hello-lock-vm/result-arch.json` (default
`~/.cache/hello-lock-vm/result-arch.json`), suite `lock-loss`, recorded
`2026-11-02T23:48:52.862260+00:00`, tested Service.qml SHA-256
`2d175c3d1b99498fc34d30948c634091974f45b6e835b0b2c0a7c99511c59315`.
The result includes all runtime source hashes and explicitly marks fingerprint
and full-shell coverage false. These result paths hold the latest run, so a
later run can replace this evidence. QEMU stopped and the disposable directory,
logs, disks and credentials were removed after this run.


2026-11-02: the CachyOS path completed the official installation, stopped the
Arch bootstrap, and booted only the installed target. The guest reported
`ID=cachyos`, kernel `7.3.1-1-cachyos`, Hyprland and no Omarchy. The complete
shared visual suite passed in the 1 GiB compact profile, and its exported
Settings frame was inspected. QEMU stopped and the disposable run directory,
installer logs, disks and credentials were removed. The returned result states
`authentication_tested: false`.

2026-11-02: Fedora 44 also passed the complete compact-mode visual suite using
its native Sway and Quickshell packages. The guest reported Fedora 44, Sway and
no Omarchy; its sample Settings frame was inspected. The run stopped its VM and
removed disposable files. The first Fedora attempt requested Hyprland, which
is absent from the current native package catalog; the Sway profile supersedes
that dependency-blocked attempt. This is visual/settings coverage, without PAM.

The Arch complete compact-mode VM pipeline passed twice, including the
final run with the memory watchdog enabled:
verified official Arch image; autonomous dependency installation; Hyprland
startup without Omarchy; all eight Settings sections; isolated persistence;
generated wordmark; image import; native dialog component compilation; custom
colors; normal/reduced-motion previews; and return to Settings. The exported
sample Settings frame was inspected. The guest stopped and its disposable run
directory was removed. Native file-chooser interaction is not exercised.

A repeat full run encountered host memory pressure and was stopped by the
watchdog. That exposed a disconnected-QMP cleanup exception, which was fixed
and covered by a regression test. A real paused KVM guest was then subjected to
injected low-memory readings; termination and disconnected-monitor cleanup
passed. The final full application rerun then passed. The injected-abort check
is fault-injection coverage, separate from the two application test passes.

The guest visual test retains the shared suite's existing LogoImage aspect
warning; a passing result means no QML errors, not a warning-free run.

## Standalone authentication suite

```sh
HELLO_LOCK_VM_SOFTWARE_GPU=1 python3 tests/vm/lab.py run --distro arch --suite standalone --tiny --wait-for-memory 900
# Other configured targets use the same explicit suite:
HELLO_LOCK_VM_SOFTWARE_GPU=1 python3 tests/vm/lab.py run --distro fedora --suite standalone --tiny --wait-for-memory 900
HELLO_LOCK_VM_SOFTWARE_GPU=1 python3 tests/vm/lab.py run --distro cachyos --suite standalone --tiny --wait-for-memory 900
```

The default `visual` suite remains auth-free. `standalone` first runs that visual
suite, then installs the managed PAM policy only inside the marked guest.
Generated credentials reach PAM through QMP's virtual keyboard. The host neither
asks for the owner's password nor controls the owner's desktop. No test IPC can
submit a password or report authentication success to the locker.

The driver proves a green desktop witness is visible and receives keyboard input
before locking. It reads the VM's virtual GPU using a private UNIX VNC socket,
then waits for actual lock-background pixels (never a QEMU inactive/blank
placeholder), checks that desktop pixels are absent while locked, and keyboard input
does not reach the underlying witness. This is independent of QML status.
Hyprland's monitor IPC additionally confirms compositor protection. Only the
virtual keyboard can supply correct/wrong passwords. The raw framebuffer reader
uses Python's standard library and exports synthetic guest frames only.

Implemented checks include repeated requests, wrong/correct passwords, forced
backend death with fresh PAM recovery, background confirmation, guest kernel s2idle suspend/resume via RTC/virtual-keyboard wakeup
(and an explicit S3 diagnostic via QMP wakeup), virtual output addition/removal with mixed scale
on Hyprland, and missing optional visual files. A result's
`authentication_checks` lists what actually completed; an implemented check is
not a passing result. Password-only PAM coverage does not establish fingerprint,
MFA or arbitrary administrator-policy compatibility.

The first real standalone authentication run passed on Arch/Hyprland on
2026-11-02 (Pacific): independent pixel/input witnesses, repeated requests,
wrong/correct passwords and backend recovery with a plain fallback. Extended
checks and other distributions require their own passing results. Hyprland
restore is enabled explicitly in the disposable guest config only.

2026-11-02 (Pacific): the complete Fedora 44/Sway standalone suite passed
with QXL, Mesa software rendering and `--tiny` (768 MiB RAM, guest swap, 1 GiB
host reserve). The kernel suspend-success counter increased from 0 to 1 during
real s2idle suspend. Post-resume pixels/input, fresh PAM authentication, and
real PAM with both optional visual QML files absent all passed. The exported
fallback frame was inspected and shows the actual Hello Lock UI. This result
covers s2idle and this virtual GPU, not deep S3 or physical hardware.

2026-11-02 (Pacific): Arch/Hyprland also passed the complete QXL/Mesa
standalone suite in a 768 MiB guest, running kernel `7.2.11-arch1-1`. In addition
to the Fedora checks, it added and removed a headless output twice, verified
scale 1.25 on the added output, and required compositor protection on every
active output. The s2idle success counter increased from 0 to 1. Its actual
fallback frame and Settings sample were inspected.

2026-11-02 (Pacific): genuine CachyOS/Hyprland passed the same complete
QXL/Mesa suite in 768 MiB after a fresh official installation and independent
boot of its target disk. It reported `ID=cachyos` and kernel
`7.3.1-1-cachyos`. All 14 authentication/display checks completed, including
mixed-scale output addition/removal, background readiness, backend recovery,
post-sleep PAM and absent visuals. The s2idle success counter increased from
0 to 1. Its actual fallback frame and Settings sample were inspected. Earlier
package-mirror failures were superseded by this passing run; official mirror
fallbacks retain mandatory package signatures.

The default virtio-GPU display fails recovery across guest sleep in this lab.
This resembles an [upstream QEMU report](https://gitlab.com/qemu-project/qemu/-/issues/2520);
that is a diagnostic inference, not proven root-cause attribution. Plain virtio
software rendering also failed recovery. Standard VGA failed the independent
pixel baseline. Earlier aggregate passes accepting QEMU's inactive placeholder
were invalidated; none establishes suspend/display support.

Use the verified QXL/Mesa fixture for standalone sleep checks:

```sh
HELLO_LOCK_VM_SOFTWARE_GPU=1 python3 tests/vm/lab.py run --distro fedora --suite standalone --tiny --wait-for-memory 900
```

The fixture's SPICE and VNC sockets are private UNIX sockets, with no network
listener. Shared visual effects still use Mesa's full software OpenGL renderer.
The guest-only root suspend helper validates the VM marker/hostname, enables
RTC/keyboard wake, and invokes `rtcwake -m freeze`. The host supplies a bounded
virtual modifier-key wake fallback; the kernel counter must increase. No
password or authentication-success hook is involved. The fixture explicitly
power-cycles guest outputs after resume and has no production idle daemon.
The expanded standalone suite also exercises swayidle timeout, logind lock and
before-sleep events, requiring a confirmed lock before kernel sleep. It does
not establish another desktop's complete power-management policy.

`HELLO_LOCK_VM_SUSPEND=s3` selects the separate systemd/QMP S3 diagnostic; its
current graphics failure remains a blocker for claiming deep-S3 support.
`--tiny` retains the same runtime memory/pressure watchdog. Earlier larger
attempts were stopped safely under host memory pressure; aborted runs are not
passes. A completed result identifies its `virtual_gpu`, RAM and exact checks.

Results are private cache records, not tracked artifacts:
`~/.cache/hello-lock-vm/result-<distro>-<suite>.json` preserves suite identity;
`result-<distro>.json` and `last-result.json` describe the latest run and may be
overwritten by another suite. Failed/aborted/deferred records are not support
claims. VM disks, logs and generated credentials are removed after each run.

Remaining coverage includes live-locker conflicts, broader compositor/distros,
broader idle-policy combinations and independent security review. Physical fingerprints,
real monitor hotplug and host power-management behavior remain outside VM
evidence. Mark these unverified rather than requiring owner participation or
treating virtual hardware as proof of physical compatibility.

## Upstream references

- [Official Arch images](https://github.com/archlinux/arch-boxes)
- [QEMU monitor and virtual input/screen control](https://www.qemu.org/docs/master/system/monitor)
- [QEMU system options](https://www.qemu.org/docs/master/system/qemu-manpage.html)
- [Cloud-init module reference](https://docs.cloud-init.io/en/latest/reference/modules.html)

- [Fedora Hyprland package availability](https://packages.fedoraproject.org/pkgs/hyprland/hyprland/)
- [Ubuntu cloud-image verification](https://ubuntu.com/docs/public-images/public-images-how-to/verify-image-checksum/)
- [Debian cloud download directory](https://cloud.debian.org/images/cloud/trixie/latest/)
- [CachyOS unattended installer configuration](https://github.com/CachyOS/New-Cli-Installer/blob/master/docs/config.md)
- [Ubuntu 26.04 package catalog](https://packages.ubuntu.com/resolute/)
