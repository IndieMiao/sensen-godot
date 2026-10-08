"""Smoke-only R2.3 packing. Leaves approved flame/spark resources untouched.

Input is the four original render_smoke.py outputs, never the packed result.
Premultiplied RGB dilation prevents dark fringes at newly softened alpha edges.
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
    # Fill transparent RGB with the neutral cloud edge colour before filtering.
    arr[arr[:, :, 3] < 12, :3] = [218, 222, 224]
    rgb = Image.fromarray(arr[:, :, :3]).filter(ImageFilter.GaussianBlur(2))
    # Erode before blur: keep lobes and a soft inward edge, not a glowing halo.
    alpha = alpha.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.GaussianBlur(4.5))
    rgba = rgb.convert('RGBA')
    rgba.putalpha(alpha)
    strip.paste(rgba, (i * 256, 0))
strip.save(ROOT / 'assets/rooms/_shared/fx/smoke_strip.png')
