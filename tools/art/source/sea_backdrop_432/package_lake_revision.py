"""Package the same-camera lake revision; preserve the v1 evidence."""
from pathlib import Path
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'output/sea-backdrop-432-v11'
CAP = OUT / 'captures'
DOC = ROOT / 'docs/design/sea-backdrop-432/v1.1'
DOC.mkdir(parents=True, exist_ok=True)
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'


def label(name, title):
    im = Image.open(CAP / name).convert('RGB')
    assert im.size == (360, 800)
    draw = ImageDraw.Draw(im)
    draw.rectangle((0, 0, 360, 57), fill='#f2f0e8')
    draw.text((10, 8), title, font=ImageFont.truetype(FONT, 16), fill='#334646')
    draw.text((10, 32), '360 x 800 | same camera / light | Mobile',
              font=ImageFont.truetype(FONT, 11), fill='#334646')
    draw.rectangle((0, 746, 360, 800), fill='#f2f0e8')
    for i, line in enumerate(['426 v1.1 + accepted 430 foam',
                              'Sea: 0 samples / 1 pass | Liu Bei']):
        draw.text((10, 754 + i * 21), line,
                  font=ImageFont.truetype(FONT, 11), fill='#334646')
    return im


before = label('lake-before-review.png', 'SGODOT-432 / Lake v1 before')
after = label('lake-default-review.png', 'SGODOT-432 / Lake v1.1')
after.save(DOC / 'lake-default-review.png')
pair = Image.new('RGB', (720, 800))
pair.paste(before, (0, 0))
pair.paste(after, (360, 0))
pair.save(DOC / 'lake-before-after.png')

# Unannotated water-only 20 x 20 pixel patches, excluding foam/geometry.
regions = {'near_shore': [295, 265, 315, 285],
           'outer_water': [295, 680, 315, 700],
           'upper_water': [20, 65, 40, 85]}
measurements = {}
for version, name in [('v1', 'lake-before-review.png'),
                      ('v1.1', 'lake-default-review.png')]:
    im = Image.open(CAP / name).convert('RGB')
    measurements[version] = {}
    for region, box in regions.items():
        sample = np.asarray(im.crop(box)).astype(float)
        saturation = np.asarray(im.crop(box).convert('HSV'))[..., 1] / 255
        measurements[version][region] = {
            'mean_rgb_255': sample.mean(axis=(0, 1)).round(3).tolist(),
            'mean_hsv_saturation': round(float(saturation.mean()), 4),
            'mean_srgb_luma': round(float((sample @ [.2126, .7152, .0722]).mean()), 3)}
assert measurements['v1.1']['near_shore']['mean_srgb_luma'] > measurements['v1.1']['outer_water']['mean_srgb_luma']
assert measurements['v1.1']['upper_water']['mean_hsv_saturation'] > measurements['v1']['upper_water']['mean_hsv_saturation']
(DOC / 'colour-samples.json').write_text(json.dumps({
    'regions_xyxy': regions, 'measurements': measurements,
    'scope': 'Rendered sRGB patch averages, not physical depth, transparency or perceptual acceptance.'
}, indent=2) + '\n')
shutil.copy2(CAP / 'render-validation.json', DOC / 'render-validation.json')
names = ['lake-default-review.png', 'lake-before-after.png']
(DOC / 'media-manifest.json').write_text(json.dumps({
    name: {'bytes': (DOC / name).stat().st_size,
           'sha256': hashlib.sha256((DOC / name).read_bytes()).hexdigest()}
    for name in names
}, indent=2) + '\n')
print(json.dumps(measurements, indent=2))
