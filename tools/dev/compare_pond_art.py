#!/usr/bin/env python3
"""Compare matching runtime captures; these metrics are NOT reference fidelity.
Requires Pillow and NumPy. Run after the native gallery and Android QA session.
"""
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else 'output/pond-pitch-2026-09-25')
CHECKS = ['engine', 'size', 'camera', 'orthographic_size', 'shader_time', 'msaa',
          'shadow_size', 'shadow_filter', 'catalog_sha256', 'water_shader_sha256']
rows = []
for path in sorted((ROOT / 'native').glob('*.png')):
    other = ROOT / 'android' / path.name
    if not other.exists():
        continue
    desktop = json.loads(path.with_suffix('.json').read_text())
    android = json.loads(other.with_suffix('.json').read_text())
    for key in CHECKS:
        assert desktop[key] == android[key], (path.stem, key, desktop[key], android[key])
    a = np.asarray(Image.open(path).convert('RGB'), dtype=np.float64)
    b = np.asarray(Image.open(other).convert('RGB'), dtype=np.float64)
    delta = np.abs(a - b)
    # The mobile safe area intentionally moves the HUD; compare 3D separately.
    world = delta[110:-100] if desktop['shot'] == 'portrait' else delta
    row = {'shot': path.stem, 'rgb_mae_255': float(delta.mean()),
           'world_rgb_mae_255': float(world.mean()),
           'channel_delta_p95': float(np.percentile(world, 95)),
           'world_pixels_max_delta_gt8_percent': float((world.max(2) > 8).mean() * 100),
           'matched_settings': CHECKS, 'native': desktop, 'android': android}
    assert row['world_rgb_mae_255'] < 1, row
    rows.append(row)
assert len(rows) == 5
(ROOT / 'parity.json').write_text(json.dumps(rows, indent=2))

font_path = Path('/System/Library/Fonts/Supplemental/Arial.ttf')
font = ImageFont.truetype(str(font_path), 24) if font_path.exists() else ImageFont.load_default()


def pair(left, right, labels, dest):
    result = Image.new('RGB', (2560, 856), '#182a28')
    draw = ImageDraw.Draw(result)
    for index, (path, label) in enumerate(zip([left, right], labels)):
        picture = ImageOps.contain(Image.open(path).convert('RGB'), (1280, 800))
        result.paste(picture, (1280 * index + (1280 - picture.width) // 2, 56 + (800 - picture.height) // 2))
        draw.text((28 + index * 1280, 15), label, fill='white', font=font)
    result.save(dest)


pair(ROOT/'native/gourd-hero.png', ROOT/'android/gourd-hero.png',
     ['Desktop / Metal / Mobile', 'Android emulator / Vulkan / Mobile'], ROOT/'desktop-android.png')
pair(ROOT/'before/gourd-hero.png', ROOT/'native/gourd-hero.png',
     ['Previous runtime', 'Updated runtime'], ROOT/'before-after.png')
reference = Path(__file__).resolve().parents[2] / 'docs/design/pond-pitch-2026-09-25/reference.png'
pair(reference, ROOT/'pitch/gourd-hero.png',
     ['Reference / art direction', 'Godot Mobile / actual scene'], ROOT/'reference-runtime.png')
pair(ROOT/'native/gourd-detail.png', ROOT/'android/gourd-detail.png',
     ['Desktop / stone and water detail', 'Android / stone and water detail'], ROOT/'detail-parity.png')
print(json.dumps([{k:v for k,v in row.items() if k not in ['native','android','matched_settings']} for row in rows], indent=2))
