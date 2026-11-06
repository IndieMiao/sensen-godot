"""Label the three actual captures and summarize the interleaved timings."""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'output/lighting-437'
CAP = OUT / 'captures'
DOC = ROOT / 'docs/design/lighting-437'
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
PRESETS = [('warm-noon', 'Warm noon', 'Original Alcatraz | sun altitude 56 deg'),
           ('cool-morning', 'Cool morning', 'Cool light | sun altitude 24 deg'),
           ('golden-dusk', 'Golden dusk', 'Golden light | sun altitude 18 deg')]
DOC.mkdir(parents=True, exist_ok=True)
for prefix, title, caption in PRESETS:
    im = Image.open(CAP / (prefix + '-default-review.png')).convert('RGB')
    if im.size != (360, 800):
        raise ValueError('Unexpected capture size')
    draw = ImageDraw.Draw(im)
    draw.rectangle((0, 0, 360, 57), fill='#f2f0e8')
    draw.text((10, 8), 'SGODOT-437 / ' + title,
              font=ImageFont.truetype(FONT, 16), fill='#334646')
    draw.text((10, 32), '360 x 800 | same camera | Vulkan Mobile',
              font=ImageFont.truetype(FONT, 11), fill='#334646')
    draw.rectangle((0, 746, 360, 800), fill='#f2f0e8')
    draw.text((10, 754), caption, font=ImageFont.truetype(FONT, 12), fill='#334646')
    draw.text((10, 776), '426 + 430 + 432 + 434 + 435 | Liu Bei',
              font=ImageFont.truetype(FONT, 11), fill='#334646')
    im.save(DOC / (prefix + '-default-review.png'))

report = json.loads((CAP / 'render-validation.json').read_text())
timings = report.pop('timing')
summary = {}
for preset in ['original', 'warm_noon', 'cool_morning', 'golden_dusk']:
    blocks = [block for block in timings if block['preset'] == preset]
    summary[preset] = {}
    for key in ['cpu_ms', 'gpu_ms']:
        values = np.array([v for block in blocks for v in block[key]])
        medians = [float(np.median(block[key])) for block in blocks]
        summary[preset][key] = {
            'samples': len(values), 'median': float(np.median(values)),
            'p95': float(np.percentile(values, 95)),
            'block_medians': medians}
(DOC / 'timing-validation.json').write_text(json.dumps({
    'renderer': report['renderer'], 'presets': summary,
    'method': '3 interleaved cycles; 45 warm-up + 90 sampled frames per block; middle order reversed; same geometry, camera, frozen water/foam. Measured SubViewport CPU/GPU time, uncapped renderer.',
    'scope': 'Deck Vulkan Mobile; viewport timing excludes present/display/compositor. Not physical phone performance or whole-game frame time.'
}, indent=2) + '\n')
(DOC / 'render-validation.json').write_text(json.dumps(report, indent=2) + '\n')
shadows = {}
for prefix, _, _ in PRESETS:
    on = np.array(Image.open(CAP / (prefix + '-default-review.png')).convert('RGB')).astype(float)
    off = np.array(Image.open(CAP / (prefix + '-shadow-off.png')).convert('RGB')).astype(float)
    delta = np.abs(on - off)
    shadows[prefix] = {'pixels_changed_over_2_rgb': int((delta.max(2) > 2).sum()),
                       'maximum_rgb_255': float(delta.max())}
(DOC / 'shadow-controls.json').write_text(json.dumps(shadows, indent=2) + '\n')
shutil.copy2(OUT / 'resource-validation.json', DOC / 'resource-validation.json')
if (OUT / 'android/smoke.json').exists():
    shutil.copy2(OUT / 'android/smoke.json', DOC / 'android-validation.json')
    (DOC / 'qa').mkdir(exist_ok=True)
    for preset in ['warm_noon', 'cool_morning', 'golden_dusk']:
        shutil.copy2(OUT / ('android/' + preset + '-viewport.png'), DOC / ('qa/android-' + preset + '.png'))
(DOC / 'media-manifest.json').write_text(json.dumps({
    str(p.relative_to(DOC)): {'bytes': p.stat().st_size,
                              'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
    for p in sorted(DOC.rglob('*.png'))
}, indent=2) + '\n')
print(json.dumps({'timing': summary, 'shadow_controls': shadows}, indent=2))
