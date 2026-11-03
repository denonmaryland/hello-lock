# Standalone packages

Hello Lock packages target a Hyprland or Sway Wayland session. Distribution
branding does not imply support for GNOME, KDE, X11 or another compositor.
Packages install files and a PAM policy; they do not enable an idle service,
edit compositor configuration or replace an existing locker automatically.

Build a local preview from this checkout, without root:

```sh
./bin/hello-lock-package --format arch --version 0.5.3 --release 0.preview1 --output-dir /absolute/output
./bin/hello-lock-package --format rpm --version 0.5.3 --release 0.preview1 --output-dir /absolute/output
./bin/hello-lock-package --format deb --version 0.5.3 --release 0.preview1 --output-dir /absolute/output
./bin/hello-lock-package --format tar --version 0.5.3 --release 0.preview1 --output-dir /absolute/output
```

The example version identifies a local candidate, not a published release.
The Omarchy manifest is unchanged. Output names are never overwritten. Each
artifact has a SHA-256 sidecar; installed files include BUILD-MANIFEST.json.
The source allowlist excludes Git metadata, private guides, runtime data,
personal settings and screenshots. Arch uses zstd; RPM requires rpmbuild.
The tar and Debian builders use Python's standard library. The tar artifact is
a filesystem payload for inspection/staging; use a native package for normal
system installation. Explicit directory modes keep restrictive installer umasks
from making the application unreadable. Fixed
SOURCE_DATE_EPOCH makes tar/Arch/Debian payload timestamps reproducible; RPM
reproducibility is not claimed.

| Family | Format | Install | Remove |
| --- | --- | --- | --- |
| Arch, CachyOS | `.pkg.tar.zst` | `sudo pacman -U FILE` | `sudo pacman -R hello-lock-standalone` |
| Fedora | `.rpm` | `sudo dnf install FILE` | `sudo dnf remove hello-lock-standalone` |
| Debian, Ubuntu | `.deb` | `sudo apt install ./FILE` | `sudo apt remove hello-lock-standalone` |

Debian-family packages are an experimental delivery format. Debian 13 and
Ubuntu 26.04 runtime support is not established by building a .deb. A compatible
Quickshell package with native Wayland/PAM modules is required; don't substitute
an arbitrary binary built against different Qt libraries. Consult
[Quickshell's installation instructions](https://quickshell.org/docs/v0.3.0/guide/install-setup/).
The lab's current Debian image-signature and Ubuntu dependency blockers remain
listed in [autonomous testing](autonomous-testing.md).

Required dependencies are declared in each package: Python, Quickshell, Qt Quick,
Qt SVG, Qt Wayland, PAM and coreutils. Optional features use swayidle (idle and
logind hooks), grim (CRT capture), curl (weather), Qt Multimedia (typing sounds)
and pw-play or paplay (cues). A compatible compositor is required separately.

The package-managed PAM file is `/etc/pam.d/hello-lock`, containing only the
managed `auth include login` policy. Existing `login` policies are not edited.
Arch backup metadata, Debian conffiles and RPM `%config(noreplace)` protect
local edits. An unrelated existing policy can cause installation to refuse or
retain that policy; Hello Lock refuses locking until its exact managed policy
is present. Review MFA/custom PAM stacks before use. Package removal preserves
preferences; modified PAM files may be retained by the package manager. Remove
packages only when unlocked and after stopping idle integration.

Run `hello-lock doctor` and review [standalone setup](standalone.md) before
starting a real lock. For packaged installs, the managed PAM policy is already
included. Source/user installs still require the separate explicit PAM helper.

## Optional idle service

The package includes a disabled user unit. In a desktop that manages
`graphical-session.target` and imports its Wayland/compositor variables into the
user manager, explicitly enable it with:

```sh
systemctl --user daemon-reload
systemctl --user enable --now hello-lock-idle.service
```

Use only one idle daemon. The launcher refuses an existing swayidle or hypridle.
For a directly launched Sway/Hyprland session without systemd graphical-session
management, start `hello-lock idle` from that session's startup configuration;
do not enable an environment-less unit and assume it works. The user-install
helper can create a unit with an absolute user-install path:

```sh
~/.local/share/hello-lock/bin/hello-lock-idle-install install
```

It only writes its own unit and refuses differing existing content. It does not
start or enable the service. To remove it, first disable/stop the service, then
run the helper's `remove` action with the same executable/timeout arguments and
reload the user manager. Package units are removed by the package manager.
