#!/usr/bin/env python3
"""Package signed, inspected Godot captures and measured dimensions for SGODOT-324."""
import csv
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT/'assets/rooms/_shared/shell_hall'
OUT = ROOT/'output/hallkit-324'
DOC = ROOT/'docs/design/poi-hallkit-324-2026-10-29'
PREFIX = 'SGODOT-324_HALLKIT_v1_'
DOC.mkdir(parents=True, exist_ok=True)
FONT = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
INK = '#263a40'
MUTED = '#56686d'
stats = json.loads((KIT/'asset_stats.json').read_text())
runtime = json.loads((OUT/'captures/godot-validation.json').read_text())
geometry = json.loads((OUT/'geometry-validation.json').read_text())
assert runtime['passed'] and geometry['passed']
assert runtime['renderer']['method'] == 'mobile'

NAMES = {'sofa_three_seat': '01 三人沙发', 'armchair': '02 单人扶手椅',
         'bench_three_seat': '03 三人长凳', 'round_side_table': '04 圆边桌',
         'round_stool': '05 圆凳', 'wall_sconce': '06 壁灯',
         'frame_portrait': '07 竖画框', 'frame_landscape': '07 横画框',
         'display_cabinet': '08 长展柜', 'display_island': '08 圆岛展柜'}
CHANGES = {
    'sofa_three_seat': '原 2 坐垫改 3 坐垫，座面 0.690 → 0.715 m；临时蓝色',
    'armchair': '截单座，基座/靠背缩短；保留扶手厚度，座面 0.715 m',
    'bench_three_seat': '黑皮革换鼠尾草绿；座面 0.715 m，压低缝线浮起',
    'round_side_table': '选 Coffee Shop 0 小直径件；落地、桌面升至 1.134 m',
    'round_stool': '修正负脚底；座面 0.661 → 0.715 m，横向不变',
    'wall_sconce': '保留几何；背板贴墙轴心，黄铜/暖白色块',
    'frame_portrait': '保留框/背板，移除立体植物；独立 2 面画心',
    'frame_landscape': '保留框/背板，移除立体风景；独立 2 面画心',
    'display_cabinet': '原柜 + 曲面玻璃；补侧/背面及细边框，台面 1.152 m',
    'display_island': '原圆岛 + 半宽曲面玻璃；补侧/背面及细边框，台面 1.152 m',
}


def font(size): return ImageFont.truetype(FONT, size)


def text(draw, xy, value, size=24, colour=INK):
    draw.text(xy, value, font=font(size), fill=colour)


def dims(values):
    return ' × '.join(f'{v:.3f}' for v in [values[0], values[2], values[1]])


def save(image, name):
    image.save(DOC/(PREFIX+name+'.png'))


def lineup():
    raw = Image.open(OUT/'captures/lineup.png').convert('RGB')
    image = Image.new('RGB', (3200, 1030), '#f6f8f7')
    image.paste(raw, (0, 100))
    draw = ImageDraw.Draw(image)
    text(draw, (55, 25), 'SGODOT-324  公共大厅复用件包  v1', 37)
    text(draw, (2400, 35), '黄忠  |  2026-10-29  |  技术检查稿', 27)
    origins = runtime['captures'][0]['screen_origins']
    for a in stats['assets']:
        x = origins[a['name']][0]
        label = NAMES[a['name']]
        width = draw.textlength(label, font=font(23))
        text(draw, (x-width/2, 775), label, 23)
    text(draw, (2850, 775), 'Basic Room 人物', 23)
    text(draw, (2870, 810), 'H = 1.745 m', 22, MUTED)
    text(draw, (55, 915), '8 类 / 10 变体    |    10,740 三角形    |    14 surface    |    单张 2048² 临时色板', 28)
    text(draw, (55, 965), '实际 Godot 4.7.2 · Vulkan Mobile · RTX 2060；正交俯角 20°。色块待 N1 定稿，随 N2 画面验收。', 24, MUTED)
    save(image, 'lineup')


def details():
    families = ['sofa', 'armchair', 'bench', 'table', 'stool', 'sconce', 'frames', 'display']
    labels = ['01 三人沙发', '02 单人扶手椅', '03 三人长凳', '04 圆边桌',
              '05 圆凳', '06 壁灯', '07 两种画框 / 独立画心', '08 两种展柜 / 独立玻璃']
    image = Image.new('RGB', (2400, 1250), '#f6f8f7')
    draw = ImageDraw.Draw(image)
    text(draw, (30, 18), 'SGODOT-324  结构近景  |  黄忠', 33)
    for i, family in enumerate(families):
        raw = Image.open(OUT/('captures/detail_'+family+'.png')).convert('RGB')
        raw = raw.resize((600, 510), Image.Resampling.LANCZOS)
        x, y = i%4*600, 75+i//4*575
        image.paste(raw, (x, y))
        text(draw, (x+20, y+515), labels[i], 23)
    text(draw, (30, 1210), '每格按内容独立取景；同一人物 H = 1.745 m。灰白背板仅为挂墙件审阅夹具，不计入资产。', 22, MUTED)
    save(image, 'details')


rows = []
for a in stats['assets']:
    provenance = json.loads((KIT/a['provenance']).read_text())
    base_key = a['sources'][0]; original = provenance['sources'][base_key]
    rows.append([NAMES[a['name']], str(a['triangles']), dims(a['dimensions_xyz_m']),
                 base_key, str(original['triangles']), dims(original['dimensions_xyz_m']), CHANGES[a['name']]])
headers = ['成品', '三角形', '宽 × 深 × 高（米）', '原件', '原三角形', '原宽 × 深 × 高（米）', '相对原件变化']
with (DOC/(PREFIX+'dimensions.csv')).open('w', newline='') as f:
    writer = csv.writer(f); writer.writerow(headers); writer.writerows(rows)
markdown = ['# SGODOT-324 尺寸与变化表', '', '黄忠 · 2026-10-29。全部尺寸解码实际 GLB 顶点得到；宽 X、深 Z、高 Y。', '',
            '| '+' | '.join(headers)+' |', '| '+' | '.join(['---']*len(headers))+' |']
markdown += ['| '+' | '.join(r)+' |' for r in rows]
markdown += ['', '玻璃罩另取 bakery/display_glass（8 面，2.160 × 0.980 × 1.190 m），改高 0.600 m，圆岛版横向缩为 50%。补闭合侧面、背面和细边框。',
             '原沙发 2,152 面；三人版增加第三块原型坐垫后 2,340 面。画框背板与框合为一个 Body，画心另一个 Artwork，各自共用同一材质和图集。',
             '座面高度与整体包围盒高度分开记录；圆凳原最低脚顶点 Y=-0.00577 m，已修正。挂墙件背面 Z=0，挂点中心 Y=0。',
             '独立件不携带房间接触 AO；摆进 N1/N2 后再匹配大厅图集与烘焙。', '']
(DOC/(PREFIX+'dimensions.md')).write_text('\n'.join(markdown))
table = Image.new('RGB', (3000, 1130), '#f6f8f7'); draw = ImageDraw.Draw(table)
text(draw, (40, 22), 'SGODOT-324  实测尺寸 / 来源变化  |  黄忠', 38)
widths = [235, 115, 350, 490, 130, 350, 1230]
xs = [25]
for w in widths: xs.append(xs[-1]+w)
for index, row in enumerate([headers]+rows):
    y = 92+index*80
    draw.rectangle((25, y, 2975, y+79), fill='#e4eceb' if index == 0 else '#f0f4f3' if index%2 else '#ffffff')
    for j, value in enumerate(row):
        size = 22 if j in [3, 6] else 24
        text(draw, (xs[j]+8, y+23), value, size)
text(draw, (40, 1010), '宽 X × 深 Z × 高 Y；米制真实顶点测量。人物 H=1.745 m；座面 0.715 m；桌面 0.65H；展柜台面 0.66H。', 25)
text(draw, (40, 1060), '玻璃来自 bakery/display_glass；图集为 Basic Room 临时色块。319 定色后重映射，随 N2 一起做画面验收。', 24, MUTED)
save(table, 'dimensions')
lineup(); details()
validation = {'author': '黄忠', 'task': 'SGODOT-324', 'geometry': geometry, 'godot': runtime,
              'scope': 'Desktop reusable-kit technical verification only; pending N1 atlas and N2 art acceptance.'}
(DOC/(PREFIX+'validation.json')).write_text(json.dumps(validation, indent=2, ensure_ascii=False)+'\n')
for imported in (OUT/'project/assets/rooms/_shared/shell_hall').glob('*.import'):
    shutil.copy2(imported, KIT/imported.name)
uid = OUT/'project/tools/art/review_hallkit_324.gd.uid'
if uid.exists(): shutil.copy2(uid, ROOT/'tools/art/review_hallkit_324.gd.uid')
media = []
for path in sorted(DOC.glob(PREFIX+'*')):
    if path.name.endswith('media-manifest.json'): continue
    item = {'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size}
    if path.suffix == '.png': item['size'] = list(Image.open(path).size)
    media.append(item)
(DOC/(PREFIX+'media-manifest.json')).write_text(json.dumps(media, indent=2)+'\n')
print('PACKAGED', DOC)
