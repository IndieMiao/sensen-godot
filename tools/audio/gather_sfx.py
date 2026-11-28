#!/usr/bin/env python3
"""SEN-C-236: the eight gathering sounds (SEN-C-234 D-558 §6, owner SEN-Q-345 Q5), synthesised here from sines,
noise and simple filters. No recorded or third-party material: the WAVs this writes are original and deterministic
(fixed seeds), so the same script always gives the same bytes.

    python3 -I tools/audio/gather_sfx.py [out_dir]     # default assets/audio/gather

Mono, 16-bit, 22 050 Hz, each well under a second. Loudness is left to the game (gather_presentation.json
common.sfx_volume_db, -6 dB, and a ±6 % pitch jitter per play); every file peaks at -1 dBFS here.
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 22050


def seconds(n: float) -> int:
    return int(n * RATE)


def envelope(n: int, attack: float, decay: float) -> list:
    """Linear attack (s) then exponential decay with time constant `decay` (s)."""
    a = max(1, seconds(attack))
    return [(i / a) if i < a else math.exp(-(i - a) / (decay * RATE)) for i in range(n)]


def noise(n: int, rng: random.Random) -> list:
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(x: list, cutoff: float) -> list:
    k = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    y, out = 0.0, []
    for v in x:
        y += k * (v - y)
        out.append(y)
    return out


def highpass(x: list, cutoff: float) -> list:
    low = lowpass(x, cutoff)
    return [a - b for a, b in zip(x, low)]


def bandpass(x: list, low: float, high: float) -> list:
    return lowpass(highpass(x, low), high)


def tone(n: int, freq, phase: float = 0.0) -> list:
    """A sine; `freq` is a number or a function of time (s) for sweeps."""
    out, p = [], phase
    for i in range(n):
        f = freq(i / RATE) if callable(freq) else freq
        p += 2.0 * math.pi * f / RATE
        out.append(math.sin(p))
    return out


def mix(*parts) -> list:
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def gain(x: list, g) -> list:
    return [v * (g[i] if isinstance(g, list) else g) for i, v in enumerate(x)]


def place(x: list, at: float, total: int) -> list:
    out = [0.0] * total
    start = seconds(at)
    for i, v in enumerate(x):
        if start + i < total:
            out[start + i] += v
    return out


def chop_hit(rng):
    """A blade into wood: a dry knock (bandpassed noise) over a short low body."""
    n = seconds(0.22)
    knock = gain(bandpass(noise(n, rng), 500, 2600), envelope(n, 0.002, 0.030))
    body = gain(tone(n, lambda t: 170 - 60 * t), envelope(n, 0.003, 0.060))
    return mix(gain(knock, 1.4), gain(body, 0.8))


def tree_crack(rng):
    """The trunk giving way: a burst of splintering clicks that gets denser, over a creak."""
    n = seconds(0.42)
    clicks = [0.0] * n
    t = 0.0
    while t < 0.38:
        click = gain(highpass(noise(seconds(0.012), rng), 1200), envelope(seconds(0.012), 0.0005, 0.003))
        clicks = mix(clicks, place(gain(click, rng.uniform(0.4, 1.0)), t, n))
        t += rng.uniform(0.006, 0.03) * (1.0 - t * 1.6 if t < 0.5 else 0.2)
    creak = gain(tone(n, lambda t: 140 + 40 * math.sin(t * 31)), envelope(n, 0.05, 0.20))
    return mix(clicks, gain(lowpass(creak, 900), 0.5))


def tree_thud(rng):
    """The tree on the ground: a heavy low thump and a little leafy hiss."""
    n = seconds(0.55)
    thump = gain(tone(n, lambda t: 85 - 35 * t), envelope(n, 0.004, 0.11))
    dirt = gain(lowpass(noise(n, rng), 420), envelope(n, 0.003, 0.09))
    leaves = gain(bandpass(noise(n, rng), 2500, 6000), envelope(n, 0.02, 0.12))
    return mix(gain(thump, 1.0), gain(dirt, 1.2), gain(leaves, 0.15))


def stone_hit(rng):
    """Pick on stone: a bright, clipped ring (inharmonic partials) and a click."""
    n = seconds(0.26)
    ring = mix(*(gain(tone(n, f), [v * a for v in envelope(n, 0.001, d)]) for f, a, d in
                 ((1850, 0.55, 0.050), (2790, 0.35, 0.035), (4180, 0.22, 0.022))))
    click = gain(highpass(noise(n, rng), 3000), envelope(n, 0.0005, 0.006))
    return mix(ring, gain(click, 0.9))


def stone_crumble(rng):
    """The rock breaking up: many small stone ticks and a gravelly rumble."""
    n = seconds(0.5)
    out = gain(lowpass(noise(n, rng), 300), envelope(n, 0.01, 0.12))
    t = 0.0
    while t < 0.42:
        size = seconds(rng.uniform(0.01, 0.03))
        grain = gain(bandpass(noise(size, rng), 900, 3500), envelope(size, 0.0005, 0.006))
        out = mix(out, place(gain(grain, rng.uniform(0.3, 0.9) * (1.0 - t)), t, n))
        t += rng.uniform(0.008, 0.035)
    return out


def rustle(rng):
    """Leaves and stems pulled: soft filtered noise breathing in and out."""
    n = seconds(0.36)
    hiss = bandpass(noise(n, rng), 1500, 5500)
    swell = [math.sin(math.pi * i / n) ** 1.5 * (0.6 + 0.4 * math.sin(2 * math.pi * 17 * i / RATE)) for i in range(n)]
    return gain(hiss, swell)


def pluck_pop(rng):
    """The plant coming out: a short downward 'pop' and a puff of soil."""
    n = seconds(0.16)
    pop = gain(tone(n, lambda t: 900 * math.exp(-t * 24) + 220), envelope(n, 0.002, 0.035))
    puff = gain(lowpass(noise(n, rng), 1200), envelope(n, 0.001, 0.02))
    return mix(pop, gain(puff, 0.5))


def item_pickup(rng):
    """Into the bag: two quick bell notes up a fifth."""
    n = seconds(0.3)
    first = gain(mix(tone(n, 880), gain(tone(n, 1760), 0.3)), envelope(n, 0.002, 0.06))
    second = place(gain(mix(tone(n, 1320), gain(tone(n, 2640), 0.25)), envelope(n, 0.002, 0.08)), 0.07, n)
    return mix(gain(first, 0.6), gain(second, 0.7))


SOUNDS = {"chop_hit": chop_hit, "tree_crack": tree_crack, "tree_thud": tree_thud, "stone_hit": stone_hit,
          "stone_crumble": stone_crumble, "rustle": rustle, "pluck_pop": pluck_pop, "item_pickup": item_pickup}


def write(path: str, x: list) -> None:
    fade = seconds(0.01)
    x = [v * (min(1.0, (len(x) - 1 - i) / fade)) for i, v in enumerate(x)]
    peak = max(abs(v) for v in x) or 1.0
    scale = 10 ** (-1 / 20) / peak
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(round(v * scale * 32767))) for v in x))


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "gather")
    os.makedirs(out, exist_ok=True)
    for i, (name, make) in enumerate(SOUNDS.items()):
        write(os.path.join(out, name + ".wav"), make(random.Random(236_000 + i)))
        print(name)


if __name__ == "__main__":
    main()
