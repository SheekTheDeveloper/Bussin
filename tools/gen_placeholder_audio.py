#!/usr/bin/env python3
"""Generate PLACEHOLDER sound effects for Busser.

These are synthesized programmer-art sounds, not final assets. They exist so the
audio system is audible and testable before a sound designer touches it, and so
nobody has to wire triggers blind.

Replacing one is a drop-in: keep the filename, put a real .wav (or .ogg, and
update the path in scripts/autoload/audio.gd) in assets/audio/. Nothing else
changes.

Run from the repo root:
    python tools/gen_placeholder_audio.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join("assets", "audio")


def _write(name, samples):
    """Write mono 16-bit PCM, clipped and normalized to avoid clicks."""
    peak = max((abs(s) for s in samples), default=1.0) or 1.0
    scale = 0.85 / peak
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767))
            for s in samples))
    print("  %-22s %5.2fs" % (name, len(samples) / RATE))


def _env(i, n, attack=0.005, decay=None):
    """Attack/decay envelope in seconds, so nothing starts or ends on a click."""
    t = i / RATE
    total = n / RATE
    decay = decay if decay is not None else total
    a = min(1.0, t / attack) if attack > 0 else 1.0
    d = max(0.0, 1.0 - (t / decay)) ** 2
    return a * d


def noise_burst(dur, decay, tone=0.0, seed=0):
    """Filtered noise; `tone` mixes in a sine for a ceramic/metallic ring."""
    rnd = random.Random(seed)
    n = int(RATE * dur)
    out, last = [], 0.0
    for i in range(n):
        white = rnd.uniform(-1.0, 1.0)
        last = last * 0.6 + white * 0.4          # cheap low-pass, softens hiss
        s = last
        if tone > 0.0:
            s += math.sin(2 * math.pi * tone * i / RATE) * 0.6
        out.append(s * _env(i, n, 0.002, decay))
    return out


def click(dur, freq, decay, seed=0):
    """Short pitched tick with a little noise on the transient."""
    rnd = random.Random(seed)
    n = int(RATE * dur)
    return [(math.sin(2 * math.pi * freq * i / RATE)
             + rnd.uniform(-0.3, 0.3) * (1.0 - i / n)) * _env(i, n, 0.001, decay)
            for i in range(n)]


def hum(dur, freq, harmonics=3):
    """Loopable low drone. Whole cycles only, so the loop point is seamless."""
    n = int(RATE * (round(dur * freq) / freq))
    out = []
    for i in range(n):
        s = sum(math.sin(2 * math.pi * freq * h * i / RATE) / (h * 1.5)
                for h in range(1, harmonics + 1))
        out.append(s * 0.5)
    return out


def bed(dur, seed=0):
    """Loopable room tone: filtered noise, faded across the seam."""
    rnd = random.Random(seed)
    n = int(RATE * dur)
    out, last = [], 0.0
    for i in range(n):
        last = last * 0.96 + rnd.uniform(-1.0, 1.0) * 0.04
        out.append(last * 0.6)
    xf = int(RATE * 0.25)
    for i in range(xf):
        f = i / xf
        out[i] = out[i] * f + out[n - xf + i] * (1.0 - f)
    return out[:n - xf]


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Generating placeholder audio into %s/ ..." % OUT)

    # Handling
    _write("grab.wav", click(0.09, 520, 0.06, seed=1))
    _write("drop.wav", click(0.14, 300, 0.11, seed=2))
    # Three clatter layers; audio.gd picks by stack size so a full run of plates
    # sounds heavier and less stable than a single one.
    _write("clatter_light.wav", noise_burst(0.16, 0.13, tone=900, seed=3))
    _write("clatter_mid.wav", noise_burst(0.26, 0.22, tone=640, seed=4))
    _write("clatter_heavy.wav", noise_burst(0.40, 0.34, tone=420, seed=5))
    _write("shatter.wav", noise_burst(0.55, 0.5, tone=1500, seed=6))

    # Tub
    _write("tub_scoop.wav", noise_burst(0.22, 0.18, tone=380, seed=7))
    _write("tub_down.wav", click(0.20, 180, 0.17, seed=8))

    # Dish pit
    _write("plate_to_pit.wav", click(0.13, 700, 0.10, seed=9))
    _write("machine_loop.wav", hum(1.0, 70, harmonics=4))
    _write("machine_done.wav", noise_burst(0.7, 0.62, tone=240, seed=10))

    # Kitchen / room
    _write("chef_bark.wav", click(0.30, 210, 0.26, seed=11))
    _write("plate_served.wav", click(0.12, 820, 0.09, seed=12))
    _write("ambience_loop.wav", bed(4.0, seed=13))

    # UI
    _write("ui_click.wav", click(0.06, 950, 0.045, seed=14))

    print("Done. These are placeholders - swap them freely, keep the filenames.")


if __name__ == "__main__":
    main()
