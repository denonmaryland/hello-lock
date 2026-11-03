# Standalone preview support

Hello Lock standalone is a technical preview for Hyprland and Sway Wayland
sessions. A distribution name alone is not a compatibility guarantee. The
Omarchy plugin remains a separate installation and release path.

## Initial preview scope

| Distribution/session | Native format | Verified configuration | Status |
| --- | --- | --- | --- |
| Arch / Hyprland | Arch package | Quickshell 0.3.2, kernel 7.2.11-arch1-1, QXL/Mesa VM | Preview, 34 guest assertions passed |
| CachyOS / Hyprland | Arch package | Genuine CachyOS installation, Quickshell 0.3.2, kernel 7.3.1-1-cachyos, QXL/Mesa VM | Preview, 34 guest assertions passed |
| Fedora 44 / Sway | RPM | Quickshell 0.2.1, kernel 6.19.10-300.fc44, QXL/Mesa with Sway pixman | Preview, 32 guest assertions passed |
| Debian 13 | Debian package builder | Signed guest installation path still required | Runtime unverified |
| Ubuntu 26.04 | Debian package builder | Compatible native Quickshell dependency unavailable in the tested package catalog | Runtime unverified |

Evidence is dated 2026-11-03 UTC. These guest runs used 1 GiB RAM and generated
test accounts without Omarchy. They cover installed native package/PAM behavior,
wrong passwords, backend recovery, optional component failures, branding,
capture cleanup, motion, idle/logind and kernel-confirmed s2idle. Hyprland also
covers virtual outputs and following its automatic motion preference. The
complete checks and runtime-payload digest appear in [release review](release-review.md).

Fedora's selected software renderer passed repeatedly. Earlier default Sway
renderer runs had intermittent display/recovery failures whose causes are not
all established. This is not evidence that physical GPU configurations pass.

GNOME, KDE Plasma, X11 and arbitrary Wayland compositors are outside this initial
scope. Fingerprint hardware and arbitrary multi-factor PAM conversations are
not standalone features; standalone supports one hidden PAM password prompt.
Do not infer the Omarchy plugin's fingerprint behavior for the standalone host.

## Install and removal

[Standalone setup](standalone.md) documents source/user installation, the
separate explicit managed PAM setup, configuration and previews.
[Packaging](packaging.md) documents local native preview package builds,
dependencies, installation and removal. Preview packages are available as [GitHub release assets](https://github.com/denonmaryland/hello-lock/releases/tag/standalone-preview-1),
not distribution repository packages. There is no remote shell installer.

Start with Settings/visual previews and `hello-lock doctor`. Real locking
requires a supported compositor and the exact managed PAM policy. Hyprland
restoration requires its documented compositor setting. Enable idle only after
reviewing the session environment and any existing idle daemon. Packages do
not enable the service. Stopping the optional idle service preserves an active
locker; remove the package only after unlocking and disabling idle integration.
Preferences are kept separately from installed program files.

## Release limitations

A compositor-forced lock release may expose a gap before userspace recovers.
Recovery is not proof of uninterrupted protection. A finite logind delay
inhibitor can also expire before a failed or slow locker becomes secure.
Deep S3, physical monitor hotplug, fingerprints, physical audio and live weather
remain unverified. Forecast/audio policy tests use fixture transports.

The separate AI review is recorded in [independent review](security-review-2026-11-03.md).
It is not a human security audit or certification. Stable-release claims must
remain narrower than the available evidence. An incident report should include
version, compositor/Quickshell versions, distro, renderer and reproduction steps;
never include passwords, private runtime files or raw authentication logs.
