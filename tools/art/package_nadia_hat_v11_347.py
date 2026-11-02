#!/usr/bin/env python3
"""Three signed revision images and a strict runtime-change scope audit."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from PIL import Image, ImageDraw
from package_npc_batch3 import font, sheet

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'docs/design/npc-parts-batch3-2026-10-29/nadia-v1.1'
BASELINE = 'ad751863b42770d4e8f70dd3889a4bca230b4b2f'
parser = argparse.ArgumentParser()
parser.add_argument('--runtime-root', type=Path, required=True)
args = parser.parse_args()
runtime = args.runtime_root.resolve()
DEST.mkdir(parents=True, exist_ok=True)
(DEST / '.gdignore').touch()
media = []
old_sheet_path = ROOT / 'docs/design/npc-parts-batch3-2026-10-29/nadia/SGODOT-347_NADIA_v1_02_nadia_hat.png'
old_sheet = Image.open(old_sheet_path).convert('RGB')
captures = runtime / 'output/npc-batch3/nadia-v11-closeups'
cards = runtime / 'output/npc-batch3/nadia-v11-cards'


def save(name, picture, title, note):
    image = Image.new('RGB', (picture.width, picture.height + 116), '#f5f6f3')
    image.paste(picture, (0, 72))
    draw = ImageDraw.Draw(image)
    draw.text((20, 10), '【赵云】SGODOT-347 · NADIA v1.1', font=font(24), fill='#243b43')
    draw.text((20, 40), title, font=font(20), fill='#243b43')
    draw.text((20, image.height - 34), note, font=font(16), fill='#526970')
    path = DEST / ('SGODOT-347_NADIA_v1.1_' + name + '.png')
    image.save(path, optimize=True)
    media.append({'issue': 347, 'name': path.name, 'path': str(path.relative_to(ROOT)),
                  'size': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})


for side, name, box in [('front', '01_hat_front', (492, 128, 952, 588)),
                        ('back', '02_hat_back', (492, 640, 952, 1100))]:
    before = old_sheet.crop(box)
    after = Image.open(captures / ('nadia_hat_after_' + side + '.png')).convert('RGB')
    save(name, sheet([('v1', before), ('v1.1', after)], 460, 2),
         ('正面' if side == 'front' else '背面') + ' · 帽子下压 2 cm / 帽口收紧',
         '左侧裁自已交 v1 游戏图；右侧同镜头新实渲。头发、纹理和节点不变，未调色。')
save('03_market_lineup', sheet([(title, Image.open(cards / (key + '_card.jpg')).convert('RGB'))
     for title, key in [('Mei', 'mei'), ('Theo', 'theo'), ('Nadia · v1.1', 'nadia_new')]], 300, 3),
     '集市同屋 · Mei / Theo / Nadia',
     '原居民卡舞台实渲；仅改 Nadia 帽子。围裙沿用 v1，未作可选改动。')

expected = {'assets/avatar/source/hairhat41_npc_nadia_baker/SM_hairHat41.fbx',
            'assets/avatar/parts/hairhat41_npc_nadia_baker_scene.tscn'}
changed = set(subprocess.check_output(['git', 'diff', '--name-only', BASELINE], cwd=runtime, text=True).splitlines())
assert changed == expected, changed
scene_path = 'assets/avatar/parts/hairhat41_npc_nadia_baker_scene.tscn'
before_scene = subprocess.check_output(['git', 'show', BASELINE + ':' + scene_path], cwd=runtime, text=True)
after_scene = (runtime / scene_path).read_text()
headers = lambda text: [line for line in text.splitlines() if line.startswith(('[node ', '[gd_scene ', '[ext_resource '))]
assert headers(before_scene) == headers(after_scene)
preserved = ['assets/avatar/parts_manifest.json', 'assets/avatar/npc_only.json',
             'assets/avatar/source/recipes_batch3.json', 'assets/rooms/tavern/room_albedo_ao.png',
             'assets/p0/outpost_npcs.json']
for path in preserved:
    assert (runtime / path).read_bytes() == subprocess.check_output(['git', 'show', BASELINE + ':' + path], cwd=runtime)
files = [{'path': p, 'sha256': hashlib.sha256((runtime / p).read_bytes()).hexdigest()} for p in sorted(changed)]
report = {'runtime_baseline': BASELINE, 'only_hat_source_and_scene_changed': True,
          'runtime_files': files, 'scene_node_ids_names_transforms_retained': True,
          'other_five_parts_and_tavern_exact': True, 'manifest_text_and_order_exact': True,
          'recipe_npc_only_and_slots_exact': True,
          'v1_image_source': str(old_sheet_path.relative_to(ROOT)),
          'v1_image_sha256': hashlib.sha256(old_sheet_path.read_bytes()).hexdigest(),
          'v1_crop_rectangles_xyxy': {'front': [492, 128, 952, 588], 'back': [492, 640, 952, 1100]}}
(DEST / 'scope-validation.json').write_text(json.dumps(report, indent=2) + '\n')
for src, target in [(ROOT / 'output/npc-batch3/nadia-v11/geometry-validation.json', 'geometry-validation.json'),
                    (runtime / 'output/npc-batch3/nadia-validation.json', 'godot-validation.json'),
                    (captures / 'render-validation.json', 'render-validation.json')]:
    shutil.copy2(src, DEST / target)
(DEST / 'media-manifest.json').write_text(json.dumps(media, indent=2) + '\n')
print('NADIA_V11_PACKAGE', len(media), 'images;', len(changed), 'runtime files')
