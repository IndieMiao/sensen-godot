import sys, json, subprocess
from PIL import Image, ImageDraw, ImageFont
T, items_json, OUT, MAP_OUT = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
items = json.load(open(items_json))['items']
newname = {'R': 'radish', 'L': 'lettuce', 'C': 'carrot', 'H': 'chamomile', 'T': 'orchard_fruit',
           'seed_R': 'seed_radish', 'seed_L': 'seed_lettuce', 'seed_C': 'seed_carrot', 'seed_H': 'seed_chamomile', 'seed_T': 'seed_fruit_tree'}
cjk = lambda sz, b=False: ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-%s.ttc' % ('Bold' if b else 'Regular'), sz, index=2)
cw, chh = 360, 250; cols = 6
rows = (len(items) + cols - 1) // cols
W = cols * cw + 80; H = 140 + rows * chh + 40
img = Image.new('RGB', (W, H), (0xF7, 0xF5, 0xEF)); d = ImageDraw.Draw(img)
d.rectangle([0, 0, W, 100], fill=(0x2B, 0x2A, 0x26))
d.text((40, 50), 'C-86 物品图标新旧对照（items.json 全部 42 件；左 = 现有，右 = 新图，各 128）', font=cjk(40, True), fill='white', anchor='lm')
mapping = []
for i, (iid, it) in enumerate(items.items()):
    x = 40 + (i % cols) * cw; y = 130 + (i // cols) * chh
    d.rounded_rectangle([x, y, x + cw - 16, y + chh - 16], radius=18, fill=(255, 255, 255))
    old = it['icon'].replace('res://', '')
    rel = old.replace('assets/ui/farm/', '').replace('/', '__')
    oldp = f'{T}/old/{rel}'
    import os
    ox, oy = x + 20, y + 20
    d.rounded_rectangle([ox, oy, ox + 140, oy + 140], radius=14, fill=(0xEE, 0xEC, 0xE5))
    reason = ''
    if old.endswith('.png') and os.path.exists(oldp):
        o = Image.open(oldp).convert('RGBA').resize((128, 128), Image.LANCZOS); img.paste(o, (ox + 6, oy + 6), o)
        if iid in ('seed_T', 'T'): reason = '借用洋甘菊图'
    else:
        reason = 'lucide 线框' if 'lucide' in old else '扁平 SVG'
        d.text((ox + 70, oy + 70), reason, font=cjk(20), fill=(0x90, 0x8E, 0x86), anchor='mm')
    nn = 'icon_item_' + newname.get(iid, iid)
    n = Image.open(f'{T}/out/items/128/{nn}.png').convert('RGBA')
    nx = x + 180
    d.rounded_rectangle([nx, oy, nx + 140, oy + 140], radius=14, fill=(0xD6, 0xD7, 0xD2))
    img.paste(n, (nx + 6, oy + 6), n)
    d.text((x + 20, y + 178), f'{it["name"]}', font=cjk(22, True), fill=(0x2B, 0x2A, 0x26))
    d.text((x + 20, y + 210), f'{iid} → {nn}', font=cjk(16), fill=(0x70, 0x6E, 0x66))
    mapping.append({'item_id': iid, 'name': it['name'], 'category': it['category'], 'old_icon': it['icon'], 'old_note': reason or None, 'new_icon': nn})
img.save(OUT, optimize=True); json.dump(mapping, open(MAP_OUT, 'w'), ensure_ascii=False, indent=1)
print(img.size, len(mapping))
