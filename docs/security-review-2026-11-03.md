# Separate security review — 2026-11-03

Reviewer: a separate AI reviewer with fresh context and read-only access.
This is independent of the implementation pass, not an independent human audit
or security certification. No external reviewer was contacted.

Reviewed runtime payload SHA-256:
`df0aea3ac37bbf4ee913579859851421872c01522f5c06a24f956d04293032a4`.
The payload remains uncommitted and unpublished. Scope: standalone supervisor,
QML lock/PAM core, idle and capture helpers, PAM/user/unit installers, package
construction, standalone tests, VM fixture structure and release documentation.
The reviewer did not rerun the full VM matrix or review the complete Omarchy
shell/plugin lifecycle.

## Result

No reproducible new security defect or release blocker was identified within
that scope. This result does not remove the existing preview limitations.

- PAM success with an armed conversation remains the release authority.
  Cosmetic finish requests cannot release a live lock.
- Lock loss clears input, grants, timers and the old PAM conversation; bounded
  recovery starts a fresh backend and authentication context.
- Private runtime validation, O_NOFOLLOW ownership files and flock preserve
  single ownership. Authenticated normal release relinquishes ownership before
  optional capture cleanup.
- Capture is bounded, generation-specific and independent of authentication.
- Idle commands quote literal arguments; explicit suspend rechecks the locked
  phase. Native package installation does not enable idle services, and package
  metadata preserves modified PAM policies.

## Independent verification

The reviewer ran 36 standalone Python tests and the standalone Node
authentication guards successfully, and recomputed the matching payload digest.
An isolated offscreen FileView experiment tested a suspected FIFO configuration
stall; it did not reproduce. That hypothesis is not recorded as a finding.
No real host lock, PAM operation, live settings change, package installation,
external communication or repository edit occurred during the review.

## Existing limits

Compositor-forced release may expose a recovery gap. Before-sleep delay
inhibitors expire, and Hyprland restoration depends on compositor configuration.
Physical GPU, fingerprint, hotplug and deep-sleep coverage remains limited.
See [release review](release-review.md) and [support scope](support.md) before
interpreting test passes as compatibility or protection guarantees.
