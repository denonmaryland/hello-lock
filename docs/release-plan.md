# Release preparation

Prepared 2026-11-03 as a local review plan. The owner subsequently authorized
committing and pushing the reviewed work. Release versions, tags, marketplace
requests and distribution uploads still require separate authorization.

## Separate release paths

1. **Existing Omarchy 0.5.4 security hotfix.** The pre-existing security worktree
   contains its own staged manifest, changelog, recovery fix and regressions.
   Keep its release process separate from the newer Studio/portability changes.
   Its original base is `b52d2c2`; do not replace its staged files with this
   checkout's versions. Recovery cannot eliminate compositor-side exposure.
2. **Plugin improvements and shared visual foundation.** Against this checkout's
   `e1dd95d` base, synchronize the same recovery change, then add instant unlock,
   overlay timing, explicit Settings reload, shared visual tokens, focused-screen
   adapter, asset provenance and helper compatibility. This layer retains the
   existing plugin ID and Omarchy contexts. The next plugin feature version is
   undecided; do not silently label it 0.5.4 or reuse a reviewed marketplace SHA.
3. **Standalone runtime and native preview packages.** Add the independent host,
   PAM supervisor, optional extras, idle/capture and packaging helpers, plus
   standalone regressions. Preserve a separate configuration profile. Local
   `0.5.3-0.preview1` artifact naming identifies the reviewed technical preview,
   not a public plugin release or distribution repository package.
4. **Disposable test infrastructure.** Add VM profiles, authentication fixtures,
   signed-image/installer paths, result validation and source-boundary tests.
   These are development tools, excluded from native application payloads.
5. **Release documentation.** Add support policy, setup/removal/package guidance,
   dated AI review, verification records, release notes and this plan.

The review bundle has five ordered binary-safe patches, explicit before/after
Git tree IDs, per-patch hashes, a plugin snapshot and a full snapshot. Patches
were applied sequentially to a separate temporary index and each resulting tree
was checked. No source-tree files, main index, branches or commits were changed
by splitting. The full existing security-worktree staged patch is preserved as
a separate artifact with its own base; it is not part of the linear five-patch
application sequence.

## Checks and scope

The isolated plugin/shared snapshot passes 53 Python tests, service JavaScript
regressions and plugin validation. The full snapshot passes 128 Python tests,
both JavaScript suites and plugin validation. The frozen standalone runtime
matches the reviewed digest in [release review](release-review.md); final guest
records passed Arch 34, CachyOS 34 and Fedora 32 assertions. A separate AI review
found no reproducible new defect within its scope; see its [dated report](security-review-2026-11-03.md).

The [support policy](support.md) limits the initial preview to tested compositor
configurations and keeps Debian/Ubuntu runtime experimental. This task does not
turn the VM results into physical-hardware or uninterrupted-security claims.

## Publication gates

Review the actual patches and candidate, decide release versions separately,
and obtain explicit authorization before committing or publishing. For Omarchy,
re-read the official marketplace rules and existing verification issue, test
the exact intended release, verify the pushed full SHA, and submit that SHA only
under the owner's publication authorization. Native preview packages need an
explicit delivery/channel decision; do not announce an install command that
points to an unpublished artifact. Retain the compositor-loss limitation and
AI-review qualification in release material. A human security audit remains
outside the completed AI review.
