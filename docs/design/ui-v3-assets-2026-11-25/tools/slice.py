"""Slice a generated sheet into per-asset PNGs (Pillow only).
usage: slice.py sheet.png cols rows outdir name1,name2,... sizes [fill=0.8]
Connected components on a 4x-reduced alpha mask; each component goes to the grid
cell containing its centroid; per cell crop to bbox, pad square so longer side = fill*canvas."""
import sys, json, hashlib, os
from collections import deque
from PIL import Image, ImageChops

sheet, cols, rows, outdir = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
names = sys.argv[5].split(','); sizes = [int(s) for s in sys.argv[6].split(',')]
fill = float(sys.argv[7]) if len(sys.argv) > 7 else 0.8
K = 4
im = Image.open(sheet).convert('RGBA'); W, H = im.size
# --- alpha clean-up (C-86): drop faint haze, make bodies fully opaque, darken soft shadows so they
# read as shadow (not glow) on dark glass. a<=8 -> 0; a>=246 -> 255; linear between.
# Pixels whose original alpha < 222 (soft shadow / outer edge) get RGB pulled to a dark warm tone
# and alpha x0.6, which keeps their look on light paper and stops the light halo on dark UI.
r_, g_, b_, a_ = im.split()
lut = [0 if v <= 8 else 255 if v >= 246 else round((v - 8) * 255 / 238) for v in range(256)]
soft = a_.point(lambda v: 255 if 8 < v < 222 else 0)
a2 = a_.point(lut)
a2 = Image.composite(a2.point(lambda v: round(v * 0.6)), a2, soft)
dark = Image.merge('RGB', [c.point(lambda v, t=t: round(v * 0.35 + t * 0.65)) for c, t in zip((r_, g_, b_), (52, 42, 34))])
rgb = Image.composite(dark, Image.merge('RGB', (r_, g_, b_)), soft)
# keep soft pixels only near a solid body (alpha>200): dilate body by ~28 px, feather 8 px.
# This removes the large faint haze clouds (alpha 9-30) the generator leaves around objects
# while keeping contact shadows and anti-aliased edges.
from PIL import ImageFilter
body = a_.point(lambda v: 255 if v > 200 else 0)
near = body.reduce(4).filter(ImageFilter.MaxFilter(15)).resize(a_.size, Image.BILINEAR).filter(ImageFilter.GaussianBlur(8))
a2 = ImageChops.multiply(a2, near)
im = Image.merge('RGBA', (*rgb.split(), a2))
alpha = im.getchannel('A')
bin_full = alpha.point(lambda v: 255 if v > 8 else 0)
small = bin_full.reduce(K)  # box average
w, h = small.size
px = small.load()
lab = [[0] * w for _ in range(h)]
comps = []  # (count, sx, sy)
cur = 0
for y in range(h):
    for x in range(w):
        if px[x, y] > 0 and lab[y][x] == 0:
            cur += 1; q = deque([(x, y)]); lab[y][x] = cur; cnt = sx = sy = 0
            while q:
                cx, cy = q.popleft(); cnt += 1; sx += cx; sy += cy
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and lab[ny][nx] == 0 and px[nx, ny] > 0:
                            lab[ny][nx] = cur; q.append((nx, ny))
            comps.append((cnt, sx / cnt, sy / cnt))
cw, ch = w / cols, h / rows
# components without any solid (alpha>200) core are haze/smoke wisps: drop them
strong = alpha.point(lambda v: 255 if v > 200 else 0).reduce(K).load()
has_core = set()
for y in range(h):
    for x in range(w):
        if lab[y][x] and strong[x, y] > 0: has_core.add(lab[y][x])
cell_of = {}
for i, (cnt, mx, my) in enumerate(comps, start=1):
    if cnt < 3 or i not in has_core: continue
    cell_of[i] = min(int(my // ch), rows - 1) * cols + min(int(mx // cw), cols - 1)
for s in sizes: os.makedirs(f'{outdir}/{s}', exist_ok=True)
report = []
for idx, name in enumerate(names):
    if name in ('', '-'): continue
    ids = {i for i, c in cell_of.items() if c == idx}
    if not ids: report.append({'name': name, 'cell': idx, 'error': 'empty cell'}); continue
    m_small = Image.new('L', (w, h), 0); mp = m_small.load()
    for y in range(h):
        row = lab[y]
        for x in range(w):
            if row[x] in ids: mp[x, y] = 255
    m_full = m_small.resize((W, H), Image.NEAREST)
    # dilate by one block so edge pixels of the object are not cut
    from PIL import ImageFilter
    m_full = m_small.filter(ImageFilter.MaxFilter(3)).resize((W, H), Image.NEAREST)
    a = ImageChops.multiply(alpha, m_full)
    bbox = a.point(lambda v: 255 if v > 8 else 0).getbbox()
    obj = im.copy(); obj.putalpha(a); obj = obj.crop(bbox)
    side = int(max(obj.size) / fill)
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    canvas.paste(obj, ((side - obj.size[0]) // 2, (side - obj.size[1]) // 2))
    c0, r0 = idx % cols, idx // cols
    edge = bbox[0] <= c0 * W / cols + 2 or bbox[2] >= (c0 + 1) * W / cols - 2 or bbox[1] <= r0 * H / rows + 2 or bbox[3] >= (r0 + 1) * H / rows - 2
    e = {'name': name, 'cell': idx, 'src_bbox': list(bbox), 'components': len(ids), 'touches_cell_edge': edge, 'src_px': [obj.size[0], obj.size[1]], 'files': {}}
    for s in sizes:
        p = f'{outdir}/{s}/{name}.png'
        canvas.resize((s, s), Image.LANCZOS).save(p, optimize=True)
        e['files'][str(s)] = {'path': f'{s}/{name}.png', 'sha256': hashlib.sha256(open(p, 'rb').read()).hexdigest()}
    report.append(e)
print(json.dumps({'sheet': os.path.basename(sheet), 'sheet_sha256': hashlib.sha256(open(sheet, 'rb').read()).hexdigest(), 'components': len(comps), 'assigned': len(cell_of), 'assets': report}, ensure_ascii=False, indent=1))
