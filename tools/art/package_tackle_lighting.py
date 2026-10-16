#!/usr/bin/env python3
"""Package the ungraded, fixed-camera lamp controls and focused evidence."""
from pathlib import Path
import ast
import hashlib
import json
import shutil
import subprocess

import numpy as np
from PIL import Image, ImageDraw
from package_tackle_review import font, signature

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / 'output/tackle-214/lighting/final'
DEST = ROOT / 'docs/design/tackle-shop-214-lighting-2026-10-16'
BASELINE = 'aace15a5e067fa447c9a82adf0b3d80f022f2d2b'
PREFIX = 'SGODOT-214_TACKLE_v1_1_'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / '.gdignore').touch()
    images = {name: Image.open(RAW / (name + '.png')).convert('RGB') for name in
              ['lamps-off', 'lamps-on', 'wall-only', 'pendant-only', 'lamps-off-repeat']}
    arrays = {name: np.asarray(im).astype(float) for name, im in images.items()}
    report = json.loads((RAW / 'lighting-validation.json').read_text())
    assert not report['failures'] and report['renderer'] == 'mobile'
    assert np.array_equal(arrays['lamps-off'], arrays['lamps-off-repeat']), 'Toggle is not reversible'

    # Receiving surfaces only: neither patch contains a lamp bulb or fixture.
    patches = {'wall_plaster': [335, 377, 357, 409], 'counter_worktop': [810, 592, 833, 615]}
    measurements = {}
    for name, (x0, y0, x1, y1) in patches.items():
        samples = {state: a[y0:y1, x0:x1] for state, a in arrays.items()}
        off = samples['lamps-off']
        luminance = np.array([.2126, .7152, .0722])
        states = {}
        for state, a in samples.items():
            states[state] = {
                'mean_rgb8': a.mean(axis=(0, 1)).round(3).tolist(),
                'mean_display_luma8_delta_from_off': round(float(((a - off) @ luminance).mean()), 3),
                'white_pixels_all_channels_ge_250': int(np.all(a >= 250, axis=2).sum()),
            }
        own = 'wall-only' if name == 'wall_plaster' else 'pendant-only'
        other = 'pendant-only' if name == 'wall_plaster' else 'wall-only'
        assert states[own]['mean_display_luma8_delta_from_off'] > 12, (name, states)
        assert abs(states[other]['mean_display_luma8_delta_from_off']) < 1, (name, states)
        assert states['lamps-on']['white_pixels_all_channels_ge_250'] == 0
        measurements[name] = {'rectangle_xyxy': patches[name], 'states': states}

    current = json.loads((ROOT / 'assets/rooms/tackle_shop/layout.json').read_text())
    baseline = json.loads(subprocess.check_output(
        ['git', 'show', BASELINE + ':assets/rooms/tackle_shop/layout.json'], cwd=ROOT))
    assert current.pop('local_lights') != baseline.pop('local_lights')
    assert current == baseline, 'A layout field outside the lamp specs changed'
    layout = json.loads((ROOT / 'assets/rooms/tackle_shop/layout.json').read_text())
    tree = ast.parse((ROOT / 'tools/art/build_tackle_shop.py').read_text())
    specs = [ast.literal_eval(node.value) for node in ast.walk(tree) if isinstance(node, ast.Assign)
             and any(isinstance(t, ast.Subscript) and isinstance(t.slice, ast.Constant)
                     and t.slice.value == 'local_lights' for t in node.targets)]
    assert specs == [layout['local_lights']], 'Generator and runtime lights disagree'

    unchanged = []
    for path in sorted((ROOT / 'assets/rooms/tackle_shop').iterdir()):
        if not path.is_file() or path.name == 'layout.json':
            continue
        relative = str(path.relative_to(ROOT))
        before = subprocess.check_output(['git', 'show', BASELINE + ':' + relative], cwd=ROOT)
        assert path.read_bytes() == before, relative
        unchanged.append({'path': relative, 'sha256': sha(before)})
    source = 'tools/art/source/tackle_shop/tackle_shop.blend'
    assert (ROOT / source).read_bytes() == subprocess.check_output(['git', 'show', BASELINE + ':' + source], cwd=ROOT)
    unchanged.append({'path': source, 'sha256': sha((ROOT / source).read_bytes())})
    rendered = []
    for relative in ['assets/rooms/tackle_shop/layout.json', 'scenes/tackle_shop/tackle_shop_art.gd']:
        payload = (ROOT / relative).read_bytes()
        assert payload == (ROOT / 'output/tackle-214/project' / relative).read_bytes()
        rendered.append({'path': relative, 'sha256': sha(payload)})

    # Full room above, explicitly labelled crops below; no exposure/color edit.
    sheet = Image.new('RGB', (1620, 1180), '#fff8f1')
    draw = ImageDraw.Draw(sheet)
    for x, state, title in [(0, 'lamps-off', '关闭局部灯'), (820, 'lamps-on', '开启局部灯')]:
        draw.text((x + 12, 4), title, fill='#654b3e', font=font(24))
        sheet.paste(images[state].resize((800, 800), Image.Resampling.LANCZOS), (x, 44))
    crop_specs = [
        ('左墙暖晕 · 关', 'lamps-off', (260, 310, 480, 500)),
        ('左墙暖晕 · 开', 'lamps-on', (260, 310, 480, 500)),
        ('吊灯照台面 · 关', 'lamps-off', (690, 485, 985, 680)),
        ('吊灯照台面 · 开', 'lamps-on', (690, 485, 985, 680)),
    ]
    for i, (label, state, box) in enumerate(crop_specs):
        x = i * 410
        draw.text((x + 12, 858), label + '（局部裁切）', fill='#654b3e', font=font(19))
        # Enlarge only uniformly; keep the same scale for each off/on pair.
        factor = min(390 / (box[2] - box[0]), 280 / (box[3] - box[1]))
        crop = images[state].crop(box).resize(
            (round((box[2] - box[0]) * factor), round((box[3] - box[1]) * factor)), Image.Resampling.LANCZOS)
        sheet.paste(crop, (x + (390 - crop.width) // 2, 895))
    media = DEST / (PREFIX + '14_lamp_control.png')
    signature(sheet, '灯光补正 · 左墙暖晕 / 柜台暖光',
              'Godot Mobile / Vulkan · 同镜头、同环境与太阳；仅开关房间三盏灯。下排为原图裁切放大，未调色。',
              'v1.1 灯光补正').save(media, optimize=True)
    for name in ['lamps-off', 'lamps-on']:
        shutil.copy2(RAW / (name + '.png'), DEST / (name + '.png'))
    shutil.copy2(RAW / 'lighting-validation.json', DEST / 'lighting-validation.json')
    data = {
        'baseline_commit': BASELINE, 'off_repeat_pixel_identical': True,
        'measurement': 'Display RGB8/luma8, not scene-linear HDR or an art-acceptance score',
        'receiving_surface_patches': measurements, 'unchanged_runtime_and_source_files': unchanged,
        'layout_only_local_lights_changed': True, 'generator_matches_layout': True,
        'rendered_runtime_files': rendered,
        'raw_captures': [{'name': n, 'sha256': sha((RAW / (n + '.png')).read_bytes())} for n in images],
        'media': {'path': str(media.relative_to(ROOT)), 'name': media.name, 'size': media.stat().st_size,
                  'sha256': sha(media.read_bytes())},
    }
    (DEST / 'lighting-evidence.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'render_checks': len(report['checks']), 'failures': len(report['failures']),
                      'surface_patches': measurements, 'media': data['media']}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
