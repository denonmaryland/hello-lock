# Typing effects

What the logo does while you type your password. Each effect is one file here,
`<name>.qml` (lowercase), loaded by `LockView.qml` (and by the setup screen's preview) into
the logo's box. Config: `"typingEffect": "cells"` (default), any name here,
`"shuffle"` (a different one each lock) or `"off"`.

## Contract

The root is an `Item` that fills the logo box. The host sets:

| Property | Type | Meaning |
|---|---|---|
| `source` | Item | The logo at full brightness and final colour, already layered (`layer.enabled`). Use it as a `MultiEffect`/`ShaderEffectSource` source; never reparent or re-layer it. Same size as the effect. |
| `inkRect` | rect | Where the logo's image is actually painted inside the box (aspect-fit). |
| `level` | real | Charge target, 0..1: typed characters / 12, clamped. Already stepped per character. |
| `typedLength` | int | Characters typed (count only, never content). |
| `holding` | bool | Submitted, waiting for PAM: show full. |
| `reducedMotion` | bool | Plain fades only: no movement, scaling, shaking or particles. |
| `accent`, `logoColor`, `errorColor` | color | Theme colours. `logoColor` is the tint of `source`. |

The host calls (functions on the root):

| Function | When |
|---|---|
| `keystroke(length, delta)` | The typed length changed; `delta` is +1, -1, or -n for a clear. |
| `submit()` | Enter pressed: fill to full fast (~250 ms). `holding` turns true. |
| `fail()` | Wrong password: play the failure, then rest at level 0 (the host sets `level` to 0 too). The host also runs its own glitch and shake. |
| `reset()` | Back to uncharged without fanfare (lock shown, field cleared by the host). |

The effect exposes (read by the host):

| Property | Meaning |
|---|---|
| `baseOpacity` (real) | Opacity the host draws its own plain logo underneath at. Cells: 0.22 (dim logo, lit parts on top). An effect that draws the whole logo itself returns 0. Pulse/Off: 1. |
| `glowLevel` (real 0..1) | Drives the host's soft glow behind the logo (it grows with charge). |
| `busy` (bool) | True while animating; idle effects must stop timers and frame animations. |

Rules: theme colours only; nothing running when idle; at most a few hundred
items; 60 Hz smooth; must work for any logo (wide wordmark, square symbol,
coloured PNG with transparency); `reducedMotion` respected.

## Motion

Typing is high-frequency input, so a keystroke's response must start on the
same frame and stay light; the richer motion belongs to submit and failure.
Shared timings, so every effect feels like the same system:

| Role | Timing |
|---|---|
| Keystroke | Arrives in ~160–200 ms with an ease-out; light accents decay within ~300–450 ms. Retarget from the current value (a `Behavior`, a restarted animation, or a spring) so fast typing never queues or snaps back. No scaling of the whole logo per key. |
| Submit | Fill to full in ~250 ms, ease-out; a flash may decay a little longer. |
| Failure | ~0.5–0.7 s in all, informative rather than punishing. Error tints use the host glitch's 50 ms in / 220 ms hold / 180 ms out. Squash or breath stays within 0.95–1.05. |
| Reset | Instant, no fanfare. |
| Reduced motion | ~200 ms opacity fades only. Retargetable per-band fades (twelve rows or columns, each with its own `Behavior`) never pop when typing fast. |

Ease-out for arrivals, ease-in for departures and natural (exponential-like)
decay for light; `Linear` only for time-like progress (a failure timeline, a
sweep). Staggers stay under ~50 ms per item. Overshoot comes from a spring
(cells' pop, the equalizer and liquid simulations), never a long easing tail.

## Testing

`typing/harness/run.sh <name> [logo]` opens a small overlay window on the
screen for a few seconds with the effect on a real logo, scripts keystrokes
(type 12, backspace 3, retype, submit, fail, type 5, clear), and records it to
`/tmp/hl/fx-<name>.mp4` plus a contact sheet `/tmp/hl/fx-<name>-sheet.png`.
