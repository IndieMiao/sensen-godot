"""Prepare/publish the colour-only lake follow-up using the existing fixture."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'output/sea-backdrop-432-v12'
DOC = ROOT / 'docs/design/sea-backdrop-432/v1.2'
REL = 'assets/landmarks/_shared/sea_backdrop'
BASE = '74cbc529e9ec72eb8d2e5a527437c4a4f7bfb131'


def prepare_project():
    import prepare
    prepare.OUT = OUT
    prepare.QA = OUT / 'project'
    prepare.main()
    for name, target in [('sea_backdrop.gdshader', 'previous_sea.gdshader'),
                         ('lake.tres', 'previous_lake.tres')]:
        (prepare.QA / target).write_bytes(subprocess.check_output(
            ['git', 'show', BASE + ':' + REL + '/' + name], cwd=ROOT))


def publish():
    import colorsys
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont
    font = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    cap = OUT / 'captures'
    lake = Image.open(cap / 'lake-default-review.png').convert('RGB')
    reference = Image.open(DOC / 'reference/cmp_pond.png').convert('RGB')
    if lake.size != (360, 800) or reference.size != (810, 600):
        raise ValueError('Unexpected capture/reference dimensions')
    # Rightmost panel is the complete supplied Fern Pond screenshot.
    # Crop panel boundaries only, keep all UI, and do not adjust colour.
    pond = reference.crop((540, 0, 810, 600)).resize((360, 800), Image.Resampling.LANCZOS)
    review = lake.copy()
    draw = ImageDraw.Draw(review)
    draw.rectangle((0, 0, 360, 57), fill='#f2f0e8')
    draw.text((10, 8), 'SGODOT-432 / Lake v1.2',
              font=ImageFont.truetype(font, 16), fill='#334646')
    draw.text((10, 32), '360 x 800 | default camera | Vulkan Mobile',
              font=ImageFont.truetype(font, 11), fill='#334646')
    draw.rectangle((0, 746, 360, 800), fill='#f2f0e8')
    for y, text in [(754, 'Shallow #6FAFA0 | blue outer water retained'),
                    (775, '0 samples / 1 pass | Liu Bei')]:
        draw.text((10, y), text, font=ImageFont.truetype(font, 11), fill='#334646')
    review.save(DOC / 'lake-default-review.png')
    pair = Image.new('RGB', (720, 868), '#f2f0e8')
    pair.paste(lake, (0, 32))
    pair.paste(pond, (360, 32))
    draw = ImageDraw.Draw(pair)
    for x, text in [(10, 'Lake v1.2 / actual Mobile capture'),
                    (370, 'Fern Pond / supplied game capture')]:
        draw.text((x, 9), text, font=ImageFont.truetype(font, 14), fill='#334646')
    draw.text((10, 841), 'Fern Pond: right panel of 432 cmp_pond.png; 270 x 600 -> 360 x 800; no colour edits.',
              font=ImageFont.truetype(font, 12), fill='#334646')
    pair.save(DOC / 'lake-fern-pond-comparison.png')
    box = (295, 265, 315, 285)
    samples = {}
    for version, file in [('v1.1', 'lake-before-review.png'), ('v1.2', 'lake-default-review.png')]:
        rgb = np.asarray(Image.open(cap / file).convert('RGB').crop(box)).mean((0, 1))
        hsv = colorsys.rgb_to_hsv(*(rgb / 255))
        samples[version] = {'mean_rgb_255': rgb.tolist(), 'mean_rgb_hsv': list(hsv)}
    (DOC / 'colour-validation.json').write_text(json.dumps({
        'patch_xyxy': box, 'samples': samples,
        'rendered_saturation_ratio': samples['v1.2']['mean_rgb_hsv'][1] / samples['v1.1']['mean_rgb_hsv'][1],
        'reference_attachment': '31f7aa8a-4d7b-487a-adda-7dc9c6b74ec1',
        'reference_sha256': hashlib.sha256((DOC / 'reference/cmp_pond.png').read_bytes()).hexdigest(),
        'reference_crop_xyxy': [540, 0, 810, 600],
        'reference_resize': '4/3 Lanczos; no colour edits; complete panel including UI',
        'scope': 'Rendered patch observation, not pixel registration or art acceptance.'
    }, indent=2) + '\n')
    shutil.copy2(cap / 'render-validation.json', DOC / 'render-validation.json')
    (DOC / 'media-manifest.json').write_text(json.dumps({
        str(p.relative_to(DOC)): {'bytes': p.stat().st_size,
                                  'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
        for p in sorted(DOC.rglob('*.png'))
    }, indent=2) + '\n')


if __name__ == '__main__':
    {'prepare': prepare_project, 'publish': publish}[sys.argv[1]]()
