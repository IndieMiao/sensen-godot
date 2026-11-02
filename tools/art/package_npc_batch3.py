#!/usr/bin/env python3
"""Signed phase-one game renders and exact-source evidence for SGODOT-362."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'docs/design/npc-parts-batch3-2026-10-29'
FONT = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
BASELINE = 'f0cde4aa9d9bc56d2b35aa6634c568862f482173'


def font(size): return ImageFont.truetype(FONT, size)


def sheet(items, width=300, columns=4):
    rows = (len(items) + columns - 1) // columns
    height = max(round(im.height * width / im.width) for _, im in items)
    image = Image.new('RGB', (columns * (width + 16) + 16, rows * (height + 52) + 16), '#f5f6f3')
    draw = ImageDraw.Draw(image)
    for i, (name, source) in enumerate(items):
        x = 16 + (i % columns) * (width + 16)
        y = 16 + (i // columns) * (height + 52)
        draw.text((x, y), name, font=font(20), fill='#243b43')
        source = source.resize((width, round(source.height * width / source.width)), Image.Resampling.LANCZOS)
        image.paste(source, (x, y + 40))
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime-root', type=Path, required=True)
    args = parser.parse_args()
    runtime = args.runtime_root.resolve()
    source = runtime / 'output/npc-batch3'
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / '.gdignore').touch()
    media = []

    def save(name, picture, title, note):
        result = Image.new('RGB', (picture.width, picture.height + 116), '#f5f6f3')
        result.paste(picture, (0, 72))
        draw = ImageDraw.Draw(result)
        draw.text((20, 10), '【赵云】SGODOT-362 · NPC PARTS v1', font=font(24), fill='#243b43')
        draw.text((20, 40), title, font=font(20), fill='#243b43')
        draw.text((20, result.height - 34), note, font=font(17), fill='#526970')
        path = DEST / ('SGODOT-362_PARTS_v1_' + name + '.png')
        result.save(path, optimize=True)
        media.append({'name': path.name, 'path': str(path.relative_to(ROOT)), 'size': path.stat().st_size,
                      'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})

    def card(name): return Image.open(source / 'portraits' / (name + '_card.jpg')).convert('RGB')
    save('01_before_after', sheet([(label, card(key)) for label, key in
         [('Lena · 原造型', 'lena_now'), ('Lena · 新雨帽', 'lena_new'),
          ('Rafa · 原造型', 'rafa_now'), ('Rafa · 新帽与横纹衫', 'rafa_new')]]),
         '居民卡舞台 · 改前 / 改后', 'farm-dev checkout · Godot 4.7.2 / Vulkan Mobile · RTX 2060 · 游戏实渲，非 2D 调色')
    for number, key, title in [('02', 'lena_hat', 'Lena · 芥末雨衣黄 / 藏青徽章'),
                                ('03', 'rafa_hat', 'Rafa · 白帽顶 / 原藏青檐 / 金带金徽'),
                                ('04', 'rafa_cloth', 'Rafa · 白底藏青横纹 / 原卡其短裤')]:
        items = []
        for side, label in [('front', '正面'), ('back', '背面')]:
            for state, text in [('before', '底件'), ('after', '新件')]:
                items.append((label + ' · ' + text, Image.open(source / 'closeups' / (key + '_' + state + '_' + side + '.png')).convert('RGB')))
        save(number + '_' + key, sheet(items, 460, 2), title,
             '同灯光 / 同镜头；640² 游戏近景缩放展示；FBX 与底件逐字节一致，未改 UV / 几何 / 骨架。')
    save('05_room_lineups', sheet([(label, card(key)) for label, key in
         [('茶馆 Ama', 'ama'), ('Hana · 已通过 A', 'hana_a'), ('Lena · 新', 'lena_new'),
          ('驿站 Sigrid', 'sigrid'), ('Pip', 'pip'), ('Sam', 'sam_now')]], 260, 3),
         '同屋辨识 · 茶馆 / 驿站', '居民卡舞台逐人实渲后并排；Hana 使用已通过方案 A；本批不修改运行时 NPC slots。')
    # Review-only crop suggestions: retain the entire wider hat in both uses.
    crops = {name: {'stamp': [38, 42, 224, 280], 'face': [34, 40, 232, 232]} for name in ['lena', 'rafa']}
    old = json.loads((runtime / 'assets/p0/art/residents/portrait_crops.json').read_text())
    panel = Image.new('RGB', (980, 650), '#f5f6f3')
    draw = ImageDraw.Draw(panel)
    for row, name in enumerate(['lena', 'rafa']):
        y = row * 320 + 12
        draw.text((20, y), name.capitalize() + ' · 原框 / 建议框', font=font(23), fill='#243b43')
        picture = card(name + '_new')
        for col, (label, data) in enumerate([('原框', old[name]), ('建议框（仅审阅）', crops[name])]):
            x = col * 480 + 24
            draw.text((x, y + 38), label, font=font(19), fill='#243b43')
            for kind, offset, sizes in [('stamp', 0, [(32, 40), (96, 120)]), ('face', 180, [(80, 80), (160, 160)])]:
                box = data[kind]; crop = picture.crop((box[0], box[1], box[0] + box[2], box[1] + box[3]))
                for k, size in enumerate(sizes):
                    img = crop.resize(size, Image.Resampling.LANCZOS)
                    at = (x + offset + ((60 if kind == 'stamp' else 100) if k else 0), y + 80)
                    if kind == 'face':
                        mask = Image.new('L', size); ImageDraw.Draw(mask).ellipse((0, 0, size[0] - 1, size[1] - 1), fill=255)
                        panel.paste(img, at, mask)
                    else: panel.paste(img, at)
            draw.text((x, y + 252), 'stamp ' + str(data['stamp']), font=font(15), fill='#526970')
            draw.text((x, y + 278), 'face ' + str(data['face']), font=font(15), fill='#526970')
    save('06_portrait_crops', panel, '邮票 32×40 / 3 倍；圆脸 80 / 160',
         '建议框纳入整顶帽子；只写审阅 fixture，正式 portrait_crops.json 由后续整合处理。')
    (DEST / 'suggested-portrait-crops.json').write_text(json.dumps(crops, indent=2) + '\n')
    for relative in ['godot-validation.json', 'script-provenance.json', 'looks-phase1.json', 'closeups/render-validation.json']:
        shutil.copy2(source / relative, DEST / Path(relative).name)
    shutil.copy2(ROOT / 'tools/art/source/npc_batch3/texture-validation.json', DEST / 'texture-validation.json')
    shutil.copy2(runtime / 'reports/report_1/results.xml', DEST / 'tests.xml')
    before = subprocess.check_output(['git', 'show', BASELINE + ':assets/avatar/parts_manifest.json'], cwd=runtime).decode()
    after = (runtime / 'assets/avatar/parts_manifest.json').read_text()
    prefix = before[:before.index('\n\t]', before.index('"parts": ['))]
    assert after.startswith(prefix), 'Existing manifest bytes changed'
    original_parts = json.loads(before)['parts']; current_parts = json.loads(after)['parts']
    assert current_parts[:len(original_parts)] == original_parts
    for row in original_parts:
        for key in ['res', 'thumb']:
            path = row[key].removeprefix('res://')
            assert (runtime / path).read_bytes() == subprocess.check_output(['git', 'show', BASELINE + ':' + path], cwd=runtime)
    evidence = {'runtime_base': BASELINE,
                'manifest_before': len(original_parts), 'manifest_after': len(current_parts),
                'existing_manifest_text_prefix_exact': True, 'existing_part_resources_and_thumbs_exact': True,
                'media': media}
    (DEST / 'phase1-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'media': len(media), 'manifest': [len(original_parts), len(current_parts)]}))


if __name__ == '__main__': main()
