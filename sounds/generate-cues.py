#!/usr/bin/env python3
"""Synthesize Hello Lock's lock, error and unlock cues with the Python stdlib.

The cues share the typing pack's voice: fixed-pitch FM pulses with decaying
modulation, a little saturation, subharmonic body and a dark double low-pass.
Each event is timed to a visual hit in the matching animation, so event times
are part of the animation contract. No samples, downloads or runtime synthesis.
Reproducible 48 kHz stereo PCM16 WAVs. Run from any directory:
  python3 sounds/generate-cues.py
  python3 sounds/generate-cues.py --only unlock-coin error
  python3 sounds/generate-cues.py --demo /path/to/cues-preview.wav
"""
import argparse
from array import array
import math
from pathlib import Path
import random
import sys
import wave

RATE = 48000
OUT = Path(__file__).resolve().parent
PEAK = 10 ** (-6 / 20)  # -6 dBFS cap, well above the -13 dBFS typing pack.
TRIM = -2.5  # dB, applied to the balanced pack (about -22 LUFS integrated).

# Voices: FM ratio, initial depth, depth decay /s, residual depth, attack /s,
# low-pass Hz, saturation (0 = clean). Inharmonic ratios for short pulses,
# near-harmonic ones for the tones that resolve each unlock.
VOICES = {
    # Low electronic knock: the typing "pulse" patch, a little heavier.
    "pulse": (2.01, 1.35, 55, 0.18, 900, 1300, 1.35),
    # Short, muted digital blip for stutters and cascades.
    "blip": (2.414, 2.3, 70, 0.30, 1100, 1700, 0),
    # Resolving tone: harmonic FM that settles into a soft, slightly hollow body.
    "tone": (2.0, 1.1, 16, 0.14, 380, 2100, 0),
    # Dark sub layer under the resolving chords and the lock.
    "sub": (1.0, 0.5, 20, 0.05, 300, 700, 1.1),
}


def biquad(samples, frequency, q=0.707):
    w = 2 * math.pi * frequency / RATE
    alpha = math.sin(w) / (2 * q)
    c = math.cos(w)
    b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    a0, a1, a2 = 1 + alpha, -2 * c, 1 - alpha
    x1 = x2 = y1 = y2 = 0.0
    result = []
    for x in samples:
        y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        result.append(y)
        x2, x1, y2, y1 = x1, x, y1, y
    return result


def voice(kind, f, decay, bright=1.0, bloom=0.0):
    """One dry event. Pitch stays constant; only modulation depth and the
    filter move. bloom > 0 opens the filter over that many seconds instead of
    sweeping pitch, for the slow legendary chord."""
    ratio, depth, depth_decay, residual, attack_rate, cutoff, drive = VOICES[kind]
    size = round(min(2.4, 5.5 / decay) * RATE)
    samples = []
    for i in range(size):
        t = i / RATE
        phase = 2 * math.pi * f * t
        index = residual + depth * math.exp(-t * depth_decay)
        modulator = math.sin(phase * ratio + 0.16 * math.sin(phase * 0.501))
        carrier = math.sin(phase + index * modulator)
        if kind == "tone":
            # A second, barely detuned operator gives slow movement, not chorus.
            twin = math.sin(phase * 1.0035 + 0.6 * index * modulator)
            body = 0.62 * carrier + 0.30 * twin + 0.08 * math.sin(phase * 0.5)
        elif kind == "sub":
            body = math.sin(phase + index * modulator)
        else:
            body = 0.78 * carrier + 0.18 * math.sin(phase * 0.5)
        if drive:
            body = math.tanh(drive * body) / math.tanh(drive)
        attack = (1 - math.exp(-t * attack_rate)) ** 2
        samples.append(attack * math.exp(-t * decay) * body)
    cut = cutoff * bright
    if not bloom:
        return biquad(biquad(samples, cut), cut)
    dark = biquad(biquad(samples, cut * 0.4), cut * 0.4)
    open_ = biquad(biquad(samples, cut * 1.25), cut * 1.25)
    return [d + (o - d) * (1 - math.exp(-i / RATE * 3 / bloom)) for i, (d, o) in enumerate(zip(dark, open_))]


def render(name, length, fade, events):
    """events: (start s, Hz, amplitude, decay /s, pan -1..1, voice[, bright[, bloom]])."""
    size = round(length * RATE)
    left, right = [0.0] * size, [0.0] * size
    for n, event in enumerate(events):
        start, f, amp, decay, pan, kind, *rest = event
        bright = rest[0] if rest else 1.0
        bloom = rest[1] if len(rest) > 1 else 0.0
        # Tiny seeded timing/tuning offsets between channels for width, so a
        # centred chord isn't a static mono beep. Never a pitch glide.
        rng = random.Random("hello-lock-cue-v4-%s-%d" % (name, n))
        offset = round(rng.uniform(0, 0.0012) * RATE)
        gains = (amp * math.sqrt((1 - pan) / 2) * 1.414, amp * math.sqrt((1 + pan) / 2) * 1.414)
        for channel, gain, tune, delay in ((left, gains[0], 1.0, 0), (right, gains[1], 1.0012, offset)):
            at = round(start * RATE) + delay
            for j, x in enumerate(voice(kind, f * tune, decay, bright, bloom)):
                if at + j >= size:
                    break
                channel[at + j] += gain * x
    for channel in (left, right):
        mean = sum(channel) / size
        for i in range(size):
            edge = min(1, i / (RATE * 0.005), (size - 1 - i) / (RATE * fade))
            channel[i] = (channel[i] - mean) * max(0, edge)
    peak = max(max(abs(x) for x in left), max(abs(x) for x in right))
    return [x * PEAK / peak for x in left], [x * PEAK / peak for x in right]


def loudness(stereo):
    """Gated mean-square level (dB) of 100 ms blocks, a stand-in for LUFS."""
    left, right = stereo
    step = RATE // 10
    blocks = [sum(a * a + b * b for a, b in zip(left[i:i + step], right[i:i + step])) / step
              for i in range(0, len(left) - step + 1, step)] or [1e-12]
    top = max(blocks)
    kept = [b for b in blocks if b > top * 0.01] or [top]
    return 10 * math.log10(sum(kept) / len(kept) + 1e-12)


# Notes (Hz): E2 82.41  A2 110  D3 146.83  E3 164.81  G3 196  A3 220
#             B3 246.94  C4 261.63  D4 293.66  E4 329.63  G4 392  A4 440
# Columns: START HZ AMP DECAY PAN VOICE [BRIGHT [BLOOM]]
CUES = {
    # Lock: the CRT power-down lands at 0.60 s. A low synth knock on D3 and a
    # darker A2 sub underneath, like a system powering off. No glide.
    "lock": (0.9, 0.08, [
        (0.60, 146.83, 1.0, 20, 0, "pulse"),
        (0.645, 110, 0.75, 16, 0, "sub"),
        (0.645, 220, 0.18, 26, 0, "tone", 0.7),
    ]),
    # Coin: a soft blip at 0.30 s, then the inner piece seats on an A3+E4
    # tone at 0.47 s; a quieter, darker pulse marks the ring as the spin
    # comes to rest at 1.0 s.
    "unlock-coin": (1.5, 0.15, [
        (0.30, 329.63, 0.35, 22, -0.3, "blip"),
        (0.47, 220, 1.0, 8.5, 0, "tone"),
        (0.47, 329.63, 0.42, 10, 0.15, "tone"),
        (0.47, 110, 0.35, 12, 0, "sub"),
        (1.0, 220, 0.3, 12, 0, "tone", 0.75),
        (1.0, 110, 0.18, 14, 0, "sub"),
    ]),
    # Assemble: two low knocks (0.04, 0.64), then an A3+D4 fourth at 0.95 s.
    "unlock-assemble": (1.58, 0.15, [
        (0.04, 98, 0.6, 24, -0.2, "pulse"),
        (0.64, 110, 0.65, 24, 0.2, "pulse"),
        (0.95, 220, 1.0, 8.5, 0, "tone"),
        (0.955, 293.66, 0.5, 9.5, 0, "tone"),
        (0.95, 110, 0.35, 12, 0, "sub"),
    ]),
    # Scan: a quiet pickup blip, then D4 with a soft A4 fifth at 0.98 s.
    "unlock-scan": (1.4, 0.12, [
        (0.84, 329.63, 0.28, 24, -0.3, "blip"),
        (0.98, 293.66, 1.0, 10.5, 0, "tone"),
        (0.98, 440, 0.26, 13, 0.1, "tone", 0.85),
        (0.98, 146.83, 0.3, 13, 0, "sub"),
    ]),
    # Glitch: three stuttered digital blips with timing/tuning jitter,
    # resolving on a B3+E4 fourth at 0.86 s.
    "unlock-glitch": (1.42, 0.12, [
        (0.13, 196, 0.45, 38, -0.4, "blip"),
        (0.205, 197.6, 0.34, 42, 0.4, "blip"),
        (0.52, 194.8, 0.4, 38, -0.1, "blip"),
        (0.86, 246.94, 1.0, 8.5, 0, "tone"),
        (0.86, 329.63, 0.45, 10, 0, "tone"),
        (0.86, 123.47, 0.3, 12, 0, "sub"),
    ]),
    # Heartbeat: a low knock at 0.05 s, then two pulses (A3+E4 at 0.76 s,
    # softer A3+D4 at 1.25 s) with sub weight, like a heartbeat.
    "unlock-heartbeat": (1.72, 0.12, [
        (0.05, 92.5, 0.5, 26, 0, "pulse"),
        (0.76, 220, 1.0, 10, 0, "tone"),
        (0.76, 329.63, 0.36, 12, 0, "tone"),
        (0.76, 110, 0.45, 14, 0, "sub"),
        (1.25, 220, 0.78, 10, 0, "tone"),
        (1.25, 293.66, 0.28, 12, 0, "tone"),
        (1.25, 110, 0.35, 14, 0, "sub"),
    ]),
    # Orbit: C4 (left) and D4 (centre-right) pulses lead in; lands at 0.90 s
    # on a G3+G4 octave on the right side.
    "unlock-orbit": (1.52, 0.15, [
        (0.62, 261.63, 0.36, 20, -0.7, "blip"),
        (0.76, 293.66, 0.42, 20, 0.3, "blip"),
        (0.90, 196, 1.0, 8, 0.25, "tone"),
        (0.90, 392, 0.3, 10, 0, "tone", 0.85),
        (0.90, 98, 0.35, 11, 0.1, "sub"),
    ]),
    # Monolith: one solemn G3+D4 fifth at 1.0 s with a heavy sub.
    "unlock-monolith": (1.45, 0.12, [
        (1.0, 196, 1.0, 10, 0, "tone"),
        (1.0, 293.66, 0.55, 11.5, 0, "tone"),
        (1.0, 98, 0.55, 11, 0, "sub"),
        (1.0, 392, 0.18, 14, 0, "tone", 0.8),
    ]),
    # Particles: tiny quiet blips scattered L/R, main A3+E4 at 1.0 s.
    "unlock-particles": (1.6, 0.15, [
        (0.22, 440, 0.13, 30, -0.6, "blip", 0.8),
        (0.38, 329.63, 0.15, 30, 0.6, "blip", 0.8),
        (0.53, 392, 0.14, 30, -0.4, "blip", 0.8),
        (0.67, 293.66, 0.16, 30, 0.5, "blip", 0.8),
        (0.81, 261.63, 0.19, 28, -0.2, "blip", 0.8),
        (1.0, 220, 1.0, 9, 0, "tone"),
        (1.0, 329.63, 0.42, 10.5, 0, "tone"),
        (1.0, 110, 0.35, 12, 0, "sub"),
    ]),
    # Warp: a quiet G3 pulse passing left, landing on a C4+G4 fifth at 0.65 s.
    "unlock-warp": (1.2, 0.15, [
        (0.50, 196, 0.36, 24, -0.6, "pulse"),
        (0.65, 261.63, 1.0, 9, 0.1, "tone"),
        (0.65, 392, 0.32, 11, 0, "tone", 0.85),
        (0.65, 130.81, 0.35, 12, 0, "sub"),
    ]),
    # Split: G3 on the left, D4 on the right, meeting on a centred fifth at 0.70 s.
    "unlock-split": (1.28, 0.15, [
        (0.52, 196, 0.42, 24, -0.85, "blip"),
        (0.61, 293.66, 0.42, 24, 0.85, "blip"),
        (0.70, 196, 1.0, 9, 0, "tone"),
        (0.70, 293.66, 0.55, 10, 0, "tone"),
        (0.70, 98, 0.35, 12, 0, "sub"),
    ]),
    # Pixels: a soft blip per landing row of the cascade (0.37-0.90 s), one
    # pitch, panned L/R and slowly opening the filter, settling on an E3+B3
    # fifth at 1.13 s as the real symbol takes over.
    "unlock-pixels": (1.75, 0.15, [
        *[(0.37 + k * 0.075, 196, 0.12 + k * 0.011, 40, (-0.5 + k * 0.1) * (1 if k % 2 else -1),
           "blip", 0.7 + k * 0.06) for k in range(8)],
        (1.13, 164.81, 1.0, 8.5, 0, "tone"),
        (1.13, 246.94, 0.5, 10, 0, "tone"),
        (1.13, 82.41, 0.4, 11, 0, "sub"),
    ]),
    # Legendary: a low strike at 0.2 s, three restrained pulses on one pitch
    # (no rising fanfare), then an A2/A3+E4 chord at 2.2 s whose filter
    # slowly opens instead of sweeping pitch.
    "unlock-legendary": (3.0, 0.3, [
        (0.20, 98, 0.55, 14, 0, "pulse"),
        (0.20, 98, 0.35, 10, 0, "sub"),
        (1.60, 220, 0.4, 18, -0.35, "blip"),
        (1.85, 220, 0.45, 18, 0, "blip"),
        (2.05, 220, 0.5, 18, 0.35, "blip"),
        (2.20, 220, 1.0, 4.2, 0, "tone", 1.0, 0.35),
        (2.20, 329.63, 0.5, 4.8, 0, "tone", 1.0, 0.35),
        (2.20, 110, 0.5, 6, 0, "sub"),
    ]),
    # Short (calm/reduced motion): a quick A3 -> D4 two-pulse tap.
    "unlock-short": (0.42, 0.08, [
        (0.0, 220, 0.8, 16, 0, "tone"),
        (0.075, 293.66, 0.8, 14, 0, "tone"),
        (0.0, 110, 0.25, 18, 0, "sub"),
    ]),
    # Error: a soft, clean C3 -> A2 fall. Informs without buzzing or punishing.
    "error": (0.28, 0.05, [
        (0.0, 130.81, 0.9, 26, 0, "tone", 0.6),
        (0.11, 110, 1.0, 24, 0, "tone", 0.6),
    ]),
}


def write_wav(path, stereo):
    left, right = stereo
    pcm = array("h", (round(max(-1, min(1, x)) * 32767) for pair in zip(left, right) for x in pair))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(path), "wb") as audio:
        audio.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
        audio.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(str(path)) as audio:
        raw = array("h", audio.readframes(audio.getnframes()))
    if sys.byteorder != "little":
        raw.byteswap()
    return [x / 32767 for x in raw[0::2]], [x / 32767 for x in raw[1::2]]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", nargs="+", choices=sorted(CUES), help="regenerate only these cues")
    parser.add_argument("--demo", type=Path, help="also render a listening preview of every cue")
    args = parser.parse_args()
    names = args.only or list(CUES)
    rendered = {name: render(name, *CUES[name]) for name in names}
    levels = {name: loudness(audio) for name, audio in rendered.items()}
    # Balance: every cue sits at the peak cap, so bring louder cues down to the
    # pack median (never up, so the cap holds). With --only, the cues already
    # on disk set the median.
    # A full run also trims the pack to sit near the earlier pack's -22 LUFS.
    on_disk = [loudness(read_wav(OUT / (n + ".wav"))) for n in CUES
               if args.only and n not in names and (OUT / (n + ".wav")).exists()]
    reference = on_disk or list(levels.values())
    target = sorted(reference)[len(reference) // 2] + (0 if on_disk else TRIM)
    for name, (left, right) in rendered.items():
        gain = 10 ** (min(0 if on_disk else TRIM, target - levels[name]) / 20)
        rendered[name] = ([x * gain for x in left], [x * gain for x in right])
        write_wav(OUT / (name + ".wav"), rendered[name])
        print("%-20s %.2fs" % (name + ".wav", CUES[name][0]))
    if args.demo:
        gap = [0.0] * round(RATE * 0.45)
        left, right = list(gap), list(gap)
        for name in names:
            # Played at the default 50% plugin volume.
            left += [x * 0.5 for x in rendered[name][0]] + gap
            right += [x * 0.5 for x in rendered[name][1]] + gap
        write_wav(args.demo, (left, right))
        print("Preview order: " + ", ".join(names))
        print(args.demo)


if __name__ == "__main__":
    main()
