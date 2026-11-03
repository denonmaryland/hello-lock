# Draft release notes

These are preparation drafts, not release announcements. Versions and public
artifact locations must be finalized before publication.

## Omarchy plugin feature update — version to be decided

Hello Lock adds an immediate unlock option after successful authentication and
an optional cap for the desktop animation. Settings saves apply through an
explicit configuration reload, including when file-watch notifications are
missed. Shared visual components retain Omarchy's live theme and focused-screen
behavior while allowing a separate standalone host.

The lock-loss recovery hotfix has a separate 0.5.4 preparation path. Include its
actual published state when finalizing this feature announcement. Recovery
cannot guarantee continuous protection if the compositor releases its lock.
Installation, enabling or code updates still require the documented shell
restart; ordinary Settings saves do not.

## Standalone technical preview — local candidate 0.5.3-0.preview1

Hello Lock's Settings, visual previews and experimental password locker can run
without Omarchy in Hyprland or Sway. Customize a wordmark or imported image,
unlock symbol, saved branding presets, typing effects, sound policy and optional
weather. The host uses a separate settings profile and real PAM password checks.

New preview capabilities include opt-in swayidle/logind integration, a guarded
suspend command, automatic motion and private best-effort CRT capture. Local
Arch/CachyOS, RPM and Debian package builders include dependency declarations,
PAM configuration metadata, checksums and source manifests. Services are not
automatically enabled, and existing desktop/idle configuration is not replaced.

Installed native-package tests passed on Arch/Hyprland, genuine CachyOS/Hyprland
and Fedora 44/Sway with the documented software renderer. Real guest checks
cover wrong/correct passwords, recovery, capture cleanup, idle/logind and
kernel-confirmed s2idle. Debian/Ubuntu runtime support is not established by
building the Debian package. See [support scope](support.md) for exact versions
and unverified hardware/features.

This is a technical preview. Compositor-forced lock loss may expose a gap before
recovery. The separate AI security review is not a human audit. No universal
Linux, physical-hardware or uninterrupted-protection claim is made. Source/user
and native package installation/removal instructions are in
[standalone setup](standalone.md) and [packaging](packaging.md).
