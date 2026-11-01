# Hello Lock sound design

The typing pack uses restrained, low-register electronic pulses. Evolving phase
and frequency modulation supply the synthetic texture; the carrier stays at a
fixed pitch. Soft attacks and dry, short releases keep repeated input understated.
There are six patches and three subtly different variations each.

| Set | Character | Carrier | File length |
| --- | --- | --- | --- |
| Pulse | Warm, gently saturated electronic pulse | 126 Hz | 130 ms |
| Phase | Compact, slightly metallic phase modulation | 148 Hz | 125 ms |
| Flux | Dense low pulse with a folding modulation layer | 108 Hz | 140 ms |
| Grain | Fine, gated electronic texture | 158 Hz | 110 ms |
| Drift | Deep, soft dual-oscillator body | 96 Hz | 145 ms |
| Circuit | Short digital pulse with a muted edge | 174 Hz | 105 ms |

The generator uses fixed-pitch carriers, inharmonic modulation, a little
saturation and subharmonic body. Only Grain uses a faint seeded noise texture.
Modulation depth decays through each pulse instead of sweeping the carrier.
There are no arpeggios, laser glides, echo or long reverb tails. Soft attacks and
exponential decay shape the envelope; a double low-pass between 1.15 and 1.8 kHz
controls brightness. The files are mono PCM16 at 48 kHz, capped below -13 dBFS
with a quiet RMS target, and tapered to zero at both ends. Overlapping tails can use up to three
preloaded voices. The player drops excess pulses instead of stealing a voice or
queuing old keystrokes. Articulation choice never depends on a typed character.

Regenerate the 18 typing WAVs with Python's standard library:

```sh
python3 sounds/generate-typing.py
python3 sounds/generate-typing.py --demo /tmp/hello-lock-typing-preview.wav
pw-play /tmp/hello-lock-typing-preview.wav
```

The demo plays a pretend eight-edit phrase for each patch in the table's order,
at the default 50% plugin volume. It contains no recorded typing. The existing
lock, unlock and error cues have their own generator, `generate-cues.py`; neither pack
uses external audio, downloads or a generation service at runtime.

## Lock, unlock and error cues

The 15 cues use the same voice as the typing pack, with more weight because they
confirm something that happened: fixed-pitch FM pulses, a little saturation,
a dark sub layer and a double low-pass between about 0.7 and 2.6 kHz. They
replaced the earlier mallet/marimba pack and keep its event timing, because
each event lands on a visual hit in the matching animation.

| Voice | Use |
| --- | --- |
| Pulse | Low knocks: the lock, assemble, heartbeat, warp and legendary lead-ins |
| Blip | Short muted digital ticks: glitch stutters, pixel rows, particles, scan/orbit/split pickups |
| Tone | The resolving body: harmonic FM with a barely detuned twin operator |
| Sub | Dark weight an octave below the resolution and under the lock |

To keep them from sounding cheesy there are no laser glides, pitch sweeps,
rising fanfares, echo or reverb tails. Resolutions are plain fifths, fourths
or octaves. The legendary unlock replaces its old rising A–D–E figure with three
pulses on one pitch and a chord whose filter opens slowly. Wrong-password
feedback is a clean, low two-step fall without saturation or buzz, so it
informs without punishing. The lock cue is a low knock over a sub as the CRT
power-down lands. Cues are stereo PCM16 at 48 kHz, peak-normalized to -6 dBFS,
balanced to the pack median, then trimmed to about -22 LUFS like the earlier
pack. Wrong-password and short cues sit slightly lower.

```sh
python3 sounds/generate-cues.py
python3 sounds/generate-cues.py --only unlock-coin error   # balanced to the files on disk
python3 sounds/generate-cues.py --demo /tmp/hello-lock-cues-preview.wav
pw-play /tmp/hello-lock-cues-preview.wav
```

Settings → Sound draws each cue's waveform from peaks precomputed from these
files, never by decoding audio at runtime. After regenerating any cue or the
first variation of a typing patch, refresh them (the test suite checks they
match):

```sh
python3 sounds/peaks.py          # writes settings/SoundPeaks.js
python3 sounds/peaks.py --check
```

## Research and adaptation

Both complete sound-related skills in [Raphael Salaja's repository](https://github.com/raphaelsalaja/skill)
were reviewed at commit `dc9eef22f13635df77d9b9e67c82aa85d52a97b7`:

- [Sounds on the Web](https://github.com/raphaelsalaja/skill/blob/dc9eef22f13635df77d9b9e67c82aa85d52a97b7/skills/sounds-on-the-web/SKILL.md)
  is an audio UX audit. Applied here: visual feedback remains primary, sound can
  be disabled, volume is independent of system volume, playback is preloaded,
  reduced motion silences typing, and frequent cues stay quieter than unlocks.
- [Generating Sounds with AI](https://github.com/raphaelsalaja/skill/blob/dc9eef22f13635df77d9b9e67c82aa85d52a97b7/skills/generating-sounds-with-ai/SKILL.md)
  is a procedural synthesis audit, rather than an AI audio API. Applied here:
  modulation gives the pulses their electronic texture, exponential decay
  avoids abrupt tails, and gain stays bounded. For the cues, weight and
  length follow the action: the error is shortest and softest, the unlocks
  last as long as their animations, and only the rare legendary runs longer. The revised brief calls for
  constant carrier pitch rather than a conspicuous pitch sweep.

The explicit request for reactive typing and a low, full sound overrides three
generic recommendations: avoiding typing audio, using very short clicks, and
placing clicks in a bright 3–6 kHz band. Here the attack is short, while the low
body releases softly for about a tenth of a second. These are intentional design
choices, with separate Off and master Sounds controls.

Browser AudioContext lifecycle advice maps to a reusable native QML player.
[Qt recommends reusing SoundEffect for low-latency WAV feedback](https://doc.qt.io/qt-6/qml-qtmultimedia-soundeffect.html).
Only [TextInput's user-edit signal](https://doc.qt.io/qt-6/qml-qtquick-textinput.html#textEdited-signal)
requests playback, so programmatic updates on other monitors stay silent.
The player lives in an optional loader, outside the PAM and unlock-release paths.
Policy is read through `hello-sound --policy` on a one-second timer only while
input is active, never in response to individual keystrokes. A stale or invalid
policy silences playback. There is no added network use.

## Isolated playback checks

Use `python3 tests/run-preview.py`, then its printed temporary path:

```sh
XDG_CONFIG_HOME=PATH/config bin/hello-config sound-save '{"quietStart":null,"quietEnd":null}'
qs ipc -p PATH call review sound pulse
qs ipc -p PATH call review soundState
qs ipc -p PATH call review soundTap
qs ipc -p PATH call review soundEngaged false
qs ipc -p PATH call review quit
```

These calls exercise only the optional audio component and disposable settings.
The service is compiled but never instantiated; no real lock or PAM call occurs.
`soundState` reports three ready voices when all three WAVs have loaded. Use
`soundEngaged true` to resume, or choose another patch with `sound`.

Earlier development choices are normalized without rewriting saved settings:
wood → pulse, clay → phase, rubber → flux, felt → grain, relay → circuit and
pluck → drift. The old material-inspired WAVs are no longer in the active pack.
