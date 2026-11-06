"""Original periodic scalar fields; no photographs, UV edits or baked sunlight.

Run with NumPy, SciPy, Pillow. Both RGB images are DATA (no sRGB conversion).
Channel packing lets three optional finishes share two 1024 textures.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[3]
OUT = ROOT / 'assets/landmarks/alcatraz_island/ground'
N = 1024
rng = np.random.default_rng(4241106)
y, x = np.mgrid[:N, :N] / N


def periodic_noise(sigma):
    a = gaussian_filter(rng.normal(size=(N, N)), sigma, mode='wrap')
    return a / max(a.std(), 1e-8)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    macro = .5 + .105 * periodic_noise(51) + .045 * periodic_noise(19) + .018 * periodic_noise(5)
    blades = np.full((N, N), .48)
    # Short paired leaf strokes, softly rounded, drawn with toroidal distances.
    for _ in range(650):
        cx, cy = rng.random(2)
        dx = (x - cx + .5) % 1 - .5
        dy = (y - cy + .5) % 1 - .5
        angle = rng.uniform(-.8, .8)
        u = dx * np.cos(angle) + dy * np.sin(angle)
        v = -dx * np.sin(angle) + dy * np.cos(angle)
        blades += rng.choice([-.18, .22]) * np.exp(-((u / .0018)**2 + (v / .006)**2)*2)
    blades += .035 * periodic_noise(2)
    soil = np.clip(.5 + .12 * periodic_noise(3) + .07 * periodic_noise(.6), 0, 1)
    Image.fromarray(np.uint8(np.clip(np.stack([macro, blades, soil], -1), 0, 1)*255)).save(OUT/'alc_ground_fields.png', optimize=True)

    # 4m repeat: staggered 1 x .5m paving. Slightly irregular, softly worn joints.
    row = np.floor(y*8).astype(int)
    fx = (x*4 + .5*(row % 2)) % 1
    fy = (y*8) % 1
    wavex = .002*np.sin(y*2*np.pi*24) + .0015*np.sin(y*2*np.pi*57)
    wavey = .002*np.sin(x*2*np.pi*17)
    distx = np.minimum(fx, 1-fx) + wavex
    disty = np.minimum(fy, 1-fy)*.5 + wavey
    dist = np.minimum(distx, disty)
    joints = 1 - np.clip((dist-.006)/.013, 0, 1)
    joints = joints*joints*(3-2*joints)
    slab = rng.uniform(.25, .75, (8, 4))[row, np.floor((x*4+.5*(row % 2)) % 4).astype(int)]
    slab += .025*periodic_noise(6)
    # Long grain along local X; no extra board joints (the dock already has them).
    phase = y*2*np.pi*34 + .9*np.sin(x*2*np.pi*2) + .35*np.sin(x*2*np.pi*5+y*2*np.pi*3)
    grain = .5 + .14*np.sin(phase) + .055*np.sin(phase*2) + .035*periodic_noise(3)
    Image.fromarray(np.uint8(np.clip(np.stack([joints, slab, grain], -1), 0, 1)*255)).save(OUT/'alc_ground_surfaces.png', optimize=True)
    print('Two original 1024 x 1024 RGB packed data textures generated.')


if __name__ == '__main__':
    main()
