"""Package the dusk-only v1.3/v1.4 comparison from unretouched Mobile captures."""
from pathlib import Path
import colorsys
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'output/lighting-437-v14'
CAP = OUT / 'captures'
DOC = ROOT / 'docs/design/lighting-437/v14'
DOC.mkdir(parents=True, exist_ok=True)
OLD = ROOT / 'docs/design/lighting-437/v13'
previous = json.loads((OLD / 'color-validation.json').read_text())
regions = {key: previous['polygons_xy'][key] for key in ['rock_lit', 'rock_shade', 'dock_top']}
regions.update(
    stair_side=[(59, 259), (64, 259), (68, 267), (70, 274), (59, 273)],
    shrub_lit=[(82, 387), (88, 387), (91, 394), (84, 395)],
    grass_side=[(20, 429), (69, 454), (69, 456), (20, 432)],
)
weights = np.array([.2126, .7152, .0722])


def measure(im):
    array = np.array(im, dtype=float)
    result = {}
    for key, poly in regions.items():
        mask = Image.new('1', im.size)
        ImageDraw.Draw(mask).polygon(poly, fill=1)
        values = array[np.array(mask)]
        mean = values.mean(0)
        result[key] = {
            'pixels': len(values), 'mean_rgb_255': mean.tolist(),
            'hex': '#' + ''.join(f'{round(v):02X}' for v in mean),
            'mean_Yprime': float(mean @ weights / 255),
            'maximum_channel_255': float(values.max()),
            'p95_maximum_channel_255': float(np.percentile(values.max(1), 95)),
            'clipped_pixels': int(np.any(values >= 255, axis=1).sum()),
        }
    return result


images = {version: Image.open(CAP / name).convert('RGB') for version, name in [
    ('v1.3', 'golden-dusk-v13.png'), ('v1.4', 'golden-dusk-default-review.png')]}
assert all(im.size == (360, 800) for im in images.values())
samples = {version: measure(im) for version, im in images.items()}
for key, sample in samples['v1.4'].items():
    sample['brightness_percent_of_v13'] = 100 * sample['mean_Yprime'] / samples['v1.3'][key]['mean_Yprime']
    if key in previous['samples']['warm-noon']:
        sample['brightness_percent_of_noon'] = 100 * sample['mean_Yprime'] / previous['samples']['warm-noon'][key]['mean_Yprime']
delta = abs(np.array(images['v1.4'], dtype=float) - np.array(images['v1.3'], dtype=float))
background = {'sky_far_max_255': float(delta[:132].max()), 'near_sea_max_255': float(delta[640:].max())}
assert max(background.values()) == 0
baseline_delta = abs(np.array(images['v1.3'], dtype=float) - np.array(Image.open(OLD / 'golden-dusk-default-review.png').convert('RGB'), dtype=float))
metrics = {
    'method': 'Fixed polygon means in unretouched 360x800 Vulkan Mobile captures. Display Y-prime = .2126R + .7152G + .0722B, not linear physical luminance. Peak and clipping counts apply to the stated patches, not the whole image.',
    'polygons_xy': regions,
    'targets': {'stair_side': '#F0B47A', 'shrub_lit': '#C9B46A', 'rock_lit_preserve': '#8D836F', 'rock_shade_noon_percent': 74, 'dock_top_previous': '#9A6F4A'},
    'samples': samples, 'unchanged_background_pixels': background,
    'v13_recapture_vs_committed': {'maximum_rgb_255': float(baseline_delta.max()), 'mean_rgb_255': float(baseline_delta.mean()), 'changed_pixels': int(np.any(baseline_delta > 0, axis=2).sum())},
    'sun_hue_degrees': colorsys.rgb_to_hsv(1, .7875, .49)[0] * 360,
}
(DOC / 'color-validation.json').write_text(json.dumps(metrics, indent=2) + '\n')
shutil.copy2(CAP / 'golden-dusk-default-review.png', DOC / 'golden-dusk-default-review.png')

board = Image.new('RGB', (720, 1080), '#f2f0e8')
draw = ImageDraw.Draw(board)
font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
font = ImageFont.truetype(font_path, 14)
for i, (version, im) in enumerate(images.items()):
    x = i * 360
    board.paste(im, (x, 50))
    draw.text((x + 12, 8), 'Golden dusk ' + version, font=ImageFont.truetype(font_path, 20), fill='#334646')
    draw.text((x + 12, 33), '360 x 800 | same camera | Vulkan Mobile', font=ImageFont.truetype(font_path, 11), fill='#334646')
    row = samples[version]
    for j, (key, label) in enumerate([('stair_side', 'Stair side'), ('shrub_lit', 'Shrub highlight'), ('grass_side', 'Grass platform side'), ('rock_lit', 'Lit rock'), ('rock_shade', 'Shaded rock'), ('dock_top', 'Dock top')]):
        suffix = ''
        if key == 'rock_shade':
            noon = previous['samples']['warm-noon'][key]['mean_Yprime']
            suffix = f" / {row[key]['mean_Yprime'] / noon * 100:.1f}% noon"
        draw.text((x + 12, 863 + j * 22), f"{label}: {row[key]['hex']}{suffix}", font=font, fill='#334646')
    sun = 'Sun H 50.3 / energy 1.73 / yaw -13' if i == 0 else 'Sun H 35.0 / energy 1.27 / yaw +4'
    draw.text((x + 12, 1002), sun, font=font, fill='#334646')
    draw.text((x + 12, 1026), f"Stair peak {row['stair_side']['maximum_channel_255']:.0f}/255; clipped {row['stair_side']['clipped_pixels']} px", font=font, fill='#334646')
draw.text((12, 1054), 'SGODOT-437 | Liu Bei | Raw renders; fixed sample polygons in color-validation.json', font=ImageFont.truetype(font_path, 12), fill='#334646')
board.save(DOC / 'golden-dusk-v13-v14.png')
for name, source in [('render-validation.json', CAP), ('resource-validation.json', OUT), ('cold-validation.json', OUT)]:
    shutil.copy2(source / name, DOC / name)
(DOC / 'media-manifest.json').write_text(json.dumps({p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(DOC.glob('*.png'))}, indent=2) + '\n')
print(json.dumps(metrics, indent=2))
