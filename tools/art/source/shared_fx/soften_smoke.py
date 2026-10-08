"""Smoke-only R2.4 packing. Leaves approved flame/spark resources untouched.

Input is the four original render_smoke.py outputs, never the packed result.
Warm near-white values retain lobe shading; transparent RGB is filled before filtering.
"""
from pathlib import Path
from PIL import Image, ImageFilter
import numpy as np

ROOT = Path(__file__).resolve().parents[4]
strip = Image.new('RGBA', (1024, 256))
for i in range(4):
    src = Image.open(ROOT / f'output/shared-fx/smoke-{i}.png').convert('RGBA')
    alpha = src.getchannel('A')
    arr = np.asarray(src).copy()
    # Remap the original neutral lobe lighting to pale warm shadows / ivory white.
    # Keep the R2.3 alpha silhouette byte-identical; only RGB changes this round.
    luma = arr[:, :, :3].astype(float).mean(axis=2)
    lo, hi = np.percentile(luma[arr[:, :, 3] > 240], [2, 98])
    weight = np.clip((luma-lo)/max(hi-lo, 1), 0, 1)[..., None]
    rgb_values = np.array([215, 212, 203]) + weight * np.array([35, 36, 41])
    rgb_values[arr[:, :, 3] < 12] = [244, 243, 239]
    rgb = Image.fromarray(rgb_values.astype('uint8')).filter(ImageFilter.GaussianBlur(2))
    # Erode before blur: keep lobes and a soft inward edge, not a glowing halo.
    alpha = alpha.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.GaussianBlur(4.5))
    rgba = rgb.convert('RGBA')
    rgba.putalpha(alpha)
    strip.paste(rgba, (i * 256, 0))
strip.save(ROOT / 'assets/rooms/_shared/fx/smoke_strip.png')
