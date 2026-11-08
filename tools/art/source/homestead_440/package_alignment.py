"""439 review: native farm captures with projected component bounds, no retouching."""
from pathlib import Path
import json, shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'output/homestead-440'
CAP = OUT / 'captures'
DOC = ROOT / 'docs/design/homestead-440/v1.3'
DOC.mkdir(parents=True, exist_ok=True)
report = json.loads((CAP / 'render-validation.json').read_text())
audit = json.loads((OUT / 'glb-validation.json').read_text())
assert all(c['passed'] for c in report['checks']) and not audit['failures']
metrics = {c['name']: c for c in report['captures']}
font = '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc'
def f(size): return ImageFont.truetype(font, size)
colors = {'porch': '#B95418', 'kitchen_wing': '#087C9C'}

def wire_box(draw, corners, x, y, color):
    # Godot AABB.get_endpoint uses binary corner coordinates.
    for a in range(8):
        for mask in (1, 2, 4):
            b = a ^ mask
            if a < b:
                line = (x + corners[a][0], y + corners[a][1],
                        x + corners[b][0], y + corners[b][1])
                draw.line(line, fill='#F4F1E8', width=3)
                draw.line(line, fill=color, width=1)

def span(bounds, axis): return f'{bounds[0][axis]:.3f}…{bounds[1][axis]:.3f}'

for variant in ('a', 'b'):
    for suffix, title in [('default', '农场默认14.5°'), ('close', '14.5°门牌近景'),
                          ('45-default', '45°方向补充')]:
        entries = [metrics[f'lv{level}-{variant}-{suffix}'] for level in (5, 8, 15)]
        for key in ('camera_size', 'camera_position', 'camera_rotation'):
            assert all(c[key] == entries[0][key] for c in entries), key
        board = Image.new('RGB', (1104, 1120), '#F4F1E8')
        d = ImageDraw.Draw(board)
        d.text((16, 8), f'SGODOT-439 / #854 · {"木作 a" if variant == "a" else "石作 b"} · {title}', font=f(24), fill='#283C36')
        d.text((16, 44), '同场地 / 同光照 / 同机位 · 每列原始360×800 · 俯角43° · #858 262533a7原件', font=f(17), fill='#40594D')
        for i, (level, capture) in enumerate(zip((5, 8, 15), entries)):
            x, y = 8 + i * 368, 112
            name = capture['name']
            im = Image.open(CAP / (name + '.png')).convert('RGB')
            assert im.size == (360, 800)
            board.paste(im, (x, y))
            d.text((x + 7, 78), f'Lv{level} · ' + ('赵云门廊' if level == 5 else '赵云门廊＋左翼' if level == 8 else '刘备整栋'), font=f(21), fill='#283C36')
            for kind, box in capture['component_boxes'].items():
                wire_box(d, box['screen_corners'], x, y, colors[kind])
            if suffix == 'default':
                for start in range(12, 348, 12):
                    d.line((x+start, y+150, x+start+6, y+150), fill='#C3443C', width=1)
                d.text((x+12, y+127), 'y=150', font=f(14), fill='#9D332B')
                tx, ty = capture['highest_pixel']
                d.ellipse((x+tx-3, y+ty-3, x+tx+3, y+ty+3), fill='#FFF8C1', outline='#283C36')
                d.text((x+242, y+ty-25), f'y={ty:.1f}', font=f(16), fill='#283C36', stroke_width=1, stroke_fill='#F4F1E8')
                for sign in capture['signs'].values():
                    assert not sign['house_occludes']
                    sx, sy = sign['screen']
                    d.ellipse((x+sx-5, y+sy-5, x+sx+5, y+sy+5), outline='#287539', width=1)
            bounds = audit['level_bounds'][variant][f'lv{level}']
            d.text((x+6, 922), f'整栋 X {span(bounds,0)}  Z {span(bounds,2)} m', font=f(14), fill='#283C36')
            porch = audit['source_components']['porch_'+variant]['bounds']
            wing = audit['source_components']['kitchen_wing_'+variant]['bounds']
            d.text((x+6, 949), f'门廊 X {span(porch,0)}', font=f(16), fill=colors['porch'])
            d.text((x+6, 972), f'          Z {span(porch,2)} m', font=f(16), fill=colors['porch'])
            if level == 5:
                d.text((x+6, 999), 'Lv5 尚无左翼；Lv8起在固定锚点加入。', font=f(15), fill=colors['kitchen_wing'])
            else:
                d.text((x+6, 999), f'左翼 X {span(wing,0)}', font=f(16), fill=colors['kitchen_wing'])
                d.text((x+6, 1022), f'          Z {span(wing,2)} m', font=f(16), fill=colors['kitchen_wing'])
            d.text((x+6, 1051), f'高度 {bounds[1][1]:.4f} m · 图中仅叠加测量标注', font=f(15), fill='#40594D')
            shutil.copy2(CAP / (name + '.png'), DOC / (name + '.png'))
        d.text((16, 1086), '橙框＝门廊；蓝框＝左翼。Lv8 / Lv15的四件三角面位置、法线、RGB逐值一致；X、Z包络相同。', font=f(16), fill='#40594D')
        board.save(DOC / f'{suffix}-{variant}-review.png')
for src in (OUT/'glb-validation.json', CAP/'render-validation.json', OUT/'cold-import.json'):
    shutil.copy2(src, DOC / src.name)
print(DOC)
