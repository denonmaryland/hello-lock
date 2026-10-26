# Logo handoff transitions

How the lock screen's logo hands over to the unlock symbol. When the lock
releases, the unlock splash opens on an exact copy of the logo (the frame
matches the lock screen's last one pixel for pixel), then plays one of these.
Each transition is one file here, `<name>.qml` (lowercase), loaded by
`UnlockSplash.qml` into each screen's splash window. The config is
`"handoff": "shuffle"` (the default) or any name listed in `handoffNames` in
`UnlockSplash.qml`. Add a new file's name there and in Settings' `handoffs`.

The choice is made when the stage is primed, at the start of the 360 ms
release gate, so the file is compiled before the lock releases. Only the
focused screen with motion on plays a transition; other screens and reduced
motion get the host's plain crossfade.

## Contract

The root is a `HandoffEffect` (`HandoffEffect.qml`), filling the splash window,
drawn above the symbol (the symbol comes in from behind it).

The host sets:

| Property | Type | Meaning |
|---|---|---|
| `source` | Item | The logo as drawn at rest (tint, glow, shadow), a texture provider. Draw it with `Piece` or as a `MultiEffect` source; never reparent it. |
| `sourceRect` | rect | Where that texture sits in the window at rest (padded around the logo). |
| `accent`, `logoColor`, `alertColor`, `backgroundColor` | color | Theme colours. |

The host calls `play()` on the first frame after release, `stop()` to freeze
(skip) and `reset()` to go back to idle. `play()` resets, sets `active` and
restarts `timeline`.

The transition exposes, and the host applies to the symbol:

| Property | Meaning |
|---|---|
| `emergeScale` | Extra scale on the symbol (1 = none). |
| `emergeX`, `emergeY` | Offset, as fractions of the symbol's size. |
| `emergeTurn` | Turn about the vertical axis, in degrees (90 = edge-on). |

These are layered on top of whatever the unlock animation does to the symbol.

Provided by `HandoffEffect`: `t` (a 0..1 progress to animate), `active`, `busy`,
`cx`/`cy` (logo centre), `prand(i, k)`, `clamp01`, `easeOut`, and the
`resetting()` signal for putting a transition's own state back. `Piece` draws a
rectangle of the logo (`px`, `py`, `pw`, `ph`, in texture pixels; the whole
logo by default) where it sits at rest; move, scale, turn or fade it.

Rules:
- Start at the rest pose and be moving on the first frame. The hand-over must
  never look frozen.
- Leave the logo fully gone within about 900 ms.
- Use theme colours only, and run no timers or animations when idle.
- Use at most a few dozen items.
- Don't toggle `MultiEffect` features (blur, colorization) mid-play, because
  that recompiles the shader. Set them per piece up front.
- Avoid naming properties `top`, `left` and so on. `Item` already has them
  (anchor lines), and the file fails to load.

If a file fails to load or throws in `play()`, the host plays its built-in
fall back instead.

## Testing

Run `python3 tests/run-preview.py`, then use
`qs ipc -p PATH call review <command>`:

```sh
logo /path/to/wordmark.svg       # e.g. from bin/hello-wordmark
handoff glitch                   # or "shuffle"
prime                            # the stage as it waits under the lock
unlock 0 false                   # play it (true = reduced motion: crossfade)
```

To check the release frame, use `fullscreen true`, `effect cells 6 false` and
`unlocking true`, then screenshot. After `prime`, screenshot again and compare
the two with `magick compare -metric AE` (expect 0). Record with
`gpu-screen-recorder` to review frames. On the live shell,
`qs ipc call lock splashPreviewHandoff <name>` plays one over the desktop.
