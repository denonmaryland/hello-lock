#!/usr/bin/env python3
"""Synthesize Hello Lock's dark electronic typing pack with the Python stdlib.

No samples, downloads, model service or runtime synthesis. Reproducible 48 kHz
mono PCM16 WAVs, three articulations per family. Run from any directory:
  python3 sounds/generate-typing.py
  python3 sounds/generate-typing.py --demo /path/to/typing-preview.wav
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
# Carrier Hz, amplitude decay /s, FM ratio, initial FM depth, residual FM
# depth, low-pass Hz, length s. Inharmonic sidebands and evolving phase give
# these a quiet electronic identity. No pitched glissandos or acoustic strikes.
FAMILIES = {
    "pulse": (126, 39, 2.01, 1.35, 0.18, 1250, 0.130),
    "phase": (148, 42, 1.414, 2.10, 0.32, 1550, 0.125),
    "flux": (108, 37, 2.73, 1.80, 0.40, 1300, 0.140),
    "grain": (158, 48, 3.17, 1.45, 0.25, 1650, 0.110),
    "drift": (96, 34, 1.503, 1.15, 0.26, 1150, 0.145),
    "circuit": (174, 52, 2.414, 2.45, 0.35, 1800, 0.105),
}


def biquad(samples, frequency, q=0.707, kind="lowpass"):
    w = 2 * math.pi * frequency / RATE
    alpha = math.sin(w) / (2 * q)
    c = math.cos(w)
    if kind == "bandpass":
        b0, b1, b2 = alpha, 0, -alpha
    else:
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    a0, a1, a2 = 1 + alpha, -2 * c, 1 - alpha
    x1 = x2 = y1 = y2 = 0.0
    result = []
    for x in samples:
        y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        result.append(y)
        x2, x1, y2, y1 = x1, x, y1, y
    return result


def synthesize(name, articulation):
    f, decay, mod_ratio, depth, residual, cutoff, length = FAMILIES[name]
    rng = random.Random("hello-lock-typing-synth-v2-" + name + str(articulation))
    # Near-identical tuning within each patch. No scale, melody or rising pitch
    # tied to typing progress; differences live mainly in the modulation depth.
    ratio = (0.994, 1.0, 1.006)[articulation]
    depth *= (0.94, 1.0, 1.06)[articulation]
    size = round(length * RATE)
    texture = biquad([rng.uniform(-1, 1) for _ in range(size)], 650, 1.3, "bandpass")
    samples = []
    for i, noise in enumerate(texture):
        t = i / RATE
        phase = 2 * math.pi * f * ratio * t
        index = residual + depth * math.exp(-t * 55)
        modulator = math.sin(phase * mod_ratio + 0.16 * math.sin(phase * 0.501))
        carrier = math.sin(phase + index * modulator)
        sub = math.sin(phase * 0.5)
        if name == "pulse":
            body = 0.72 * math.tanh(1.35 * carrier) + 0.20 * sub
        elif name == "phase":
            body = 0.70 * carrier + 0.20 * math.sin(phase * 1.007 + 0.65 * modulator)
        elif name == "flux":
            fold = math.sin(phase + index * math.sin(phase * 0.997 + 0.8 * modulator))
            body = 0.58 * carrier + 0.28 * fold + 0.14 * sub
        elif name == "grain":
            # Low-level gated texture, rather than the old noise-led knock.
            body = 0.78 * carrier + 0.09 * noise * math.sin(phase * 4.07)
        elif name == "drift":
            body = 0.62 * carrier + 0.25 * math.sin(phase * 2.003 + 0.3 * modulator) + 0.13 * sub
        else:
            body = 0.74 * carrier + 0.13 * math.sin(phase * 3.03) * math.exp(-t * 70)
        # A 2–4 ms softened attack, then a quick exponential release. Constant
        # carrier pitch, dry presentation, no laser sweep, arpeggio or echo.
        attack = (1 - math.exp(-t * 900)) ** 2
        envelope = attack * math.exp(-t * decay)
        samples.append(envelope * body)
    samples = biquad(biquad(samples, cutoff), cutoff)
    # Remove DC and taper both edges after filtering; exponential decay carries
    # the audible tail, this final taper only closes the file without a click.
    mean = sum(samples) / size
    for i, x in enumerate(samples):
        edge = min(1, i / (RATE * 0.0015), (size - 1 - i) / (RATE * 0.008))
        samples[i] = (x - mean) * max(0, edge)
    peak = max(abs(x) for x in samples)
    rms = math.sqrt(sum(x * x for x in samples) / size)
    gain = min(0.22 / peak, 0.048 / rms)  # Quieter than confirmation cues.
    return [x * gain for x in samples]


def write_wav(path, samples):
    pcm = array("h", (round(max(-1, min(1, x)) * 32767) for x in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(path), "wb") as audio:
        audio.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        audio.writeframes(pcm.tobytes())


def demo(pack):
    # A pretend eight-edit phrase for each patch, never a recorded password.
    result = [0.0] * round(RATE * 0.25)
    for name in FAMILIES:
        phrase = [0.0] * round(RATE * 2.1)
        for i, at in enumerate((0, 0.18, 0.31, 0.51, 0.65, 0.78, 1.01, 1.16)):
            for j, x in enumerate(pack[name, i % 3]):
                phrase[round(at * RATE) + j] += x * 0.5
        result.extend(phrase)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--demo", type=Path, help="also render a six-family listening preview")
    args = parser.parse_args()
    pack = {}
    for name in FAMILIES:
        for articulation in range(3):
            samples = synthesize(name, articulation)
            pack[name, articulation] = samples
            path = OUT / ("type-%s-%d.wav" % (name, articulation + 1))
            write_wav(path, samples)
            print(path.name)
    if args.demo:
        write_wav(args.demo, demo(pack))
        print("Preview order: " + ", ".join(FAMILIES))
        print(args.demo)


if __name__ == "__main__":
    main()
