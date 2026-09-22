#!/usr/bin/env python3
"""Reprocess original Sensenjoy materials at phone density, preserving style.
Run: uv run --with pillow --with numpy python tools/art/prepare_game_ui_density.py
"""
from pathlib import Path
import json
import hashlib
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'output/imagegen/game-ui-2026-09-21'
DEST = ROOT / 'assets/ui/game'
RECORD = ROOT / 'output/ui-clarity-2026-09-21/asset-density.json'

def extract(name, bounds):
    rgb = np.asarray(Image.open(SOURCE / name).convert('RGB'), dtype=np.float32) / 255.0
    key = np.minimum(rgb[:, :, 0], rgb[:, :, 2]) - rgb[:, :, 1]
    alpha = 1.0 - np.clip((key - 0.15) / 0.60, 0.0, 1.0)
    alpha[alpha < 0.15] = 0
    matte = np.array([1.0, 0.0, 1.0], dtype=np.float32)
    clean = np.clip((rgb - matte * (1 - alpha[:, :, None])) /
                    np.maximum(alpha[:, :, None], 0.01), 0, 1)
    return Image.fromarray(np.round(np.dstack([clean, alpha]) * 255).astype('uint8')).crop(bounds)

panel = extract('panel-raw.png', (131, 130, 1124, 1114))
button = extract('button-raw.png', (133, 324, 1403, 663))
channels = list(button.convert('RGB').convert('HSV').split())
channels[0] = channels[0].point(lambda hue: (hue + 62) % 256)
violet = Image.merge('HSV', channels).convert('RGB').convert('RGBA')
violet.putalpha(button.getchannel('A'))
record = {'source': 'Original Sensenjoy materials, not enlarged low-resolution runtime assets',
          'svg_raster_scale': 4, 'logical_icon_size': [24, 24], 'assets': {}}
for name, source, pixels, logical in [
    ('panel-frame.png', panel, (1024, 1016), (256, 254)),
    ('control-frame.png', panel, (512, 508), (128, 127)),
    ('button-teal.png', button, (1024, 272), (256, 68)),
    ('button-violet.png', violet, (1024, 272), (256, 68)),
    ('control-teal.png', button, (512, 136), (128, 34)),
    ('control-violet.png', violet, (512, 136), (128, 34)),
]:
    source.resize(pixels, Image.Resampling.LANCZOS).save(DEST / name)
    record['assets'][name] = {'pixels': pixels, 'logical_size': logical,
                            'sha256': hashlib.sha256((DEST / name).read_bytes()).hexdigest()}
for spec in (ROOT / 'assets/ui/icons/game').glob('*.svg.import'):
    spec.write_text(spec.read_text().replace('svg/scale=1.0', 'svg/scale=4.0'))
RECORD.parent.mkdir(parents=True, exist_ok=True)
RECORD.write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({'materials': len(record['assets']), 'source_density': '4x', 'icons': 63}))
