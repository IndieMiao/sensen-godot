"""Smoke-only R2.5 packing from the four original R2.1 cloud-mesh renders.

Run render_smoke.py in Blender first if output/shared-fx/smoke-{0..3}.png is
absent. Never run pack_sprites.py to update smoke: it also rewrites approved fire.
Only smoke_strip.png is written. RGB values compensate the review scene's ACES
mapping; the original mesh lighting remains the source of the lobe shading.
"""
from pathlib import Path
from PIL import Image, ImageFilter
import numpy as np

ROOT = Path(__file__).resolve().parents[4]
strip = Image.new('RGBA', (1024, 256))
for i in range(4):
    src = Image.open(ROOT / f'output/shared-fx/smoke-{i}.png').convert('RGBA')
    arr = np.asarray(src)
    luma = arr[:, :, :3].astype(float).mean(axis=2)
    lo, hi = np.percentile(luma[arr[:, :, 3] > 240], [12, 90])
    weight = np.clip((luma-lo)/max(hi-lo, 1), 0, 1)
    # Retain a broad shaded underside and a warm-white lit crown. Godot's ACES
    # lifts the input grey: the actual rendered values are verified separately.
    weight = (weight * weight * (3 - 2 * weight)) ** 1.2
    shadow = np.array([150, 154, 163])
    highlight = np.array([229, 225, 215])
    rgb = Image.fromarray((shadow + weight[..., None] * (highlight-shadow)).astype('uint8'))
    # Same erosion/50%-alpha outline as R2.4; only reduce the broad feather.
    # ~3px 10-90% alpha width, versus ~80px equivalent cloud radius (<10%).
    alpha = src.getchannel('A').filter(ImageFilter.MinFilter(9)).filter(ImageFilter.GaussianBlur(1.1))
    rgba = rgb.convert('RGBA')
    rgba.putalpha(alpha)
    strip.paste(rgba, (i * 256, 0))
strip.save(ROOT / 'assets/rooms/_shared/fx/smoke_strip.png')
