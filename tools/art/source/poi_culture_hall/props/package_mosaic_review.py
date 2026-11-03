"""Package the colour-only mosaic revision and the exact rendered floor provenance."""
from pathlib import Path
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4];OUT=ROOT/'output/culture-mosaic-323'
DOC=ROOT/'docs/design/poi-culture-props-323-2026-11-03/v1.2';DOC.mkdir(parents=True,exist_ok=True)
godot=json.loads((OUT/'captures/validation.json').read_text())
revision=json.loads((OUT/'color-geometry-validation.json').read_text())
geometry=json.loads((ROOT/'output/culture-props-323/geometry-validation.json').read_text())
source=json.loads((ROOT/'output/culture-props-323/source-validation.json').read_text())
assert all(r['passed'] for r in [godot,revision,geometry,source])
assert 'ERROR:' not in (OUT/'render.log').read_text()
font='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
title=ImageFont.truetype(font,30);small=ImageFont.truetype(font,22)
files=[];prefix='SGODOT-323_props_v1.2_'
for name,heading,note in [
    ('mosaic_topdown','拼花正俯视','四道暖色环 + 稍深圆心 / 原石缝保留 / 仅改顶点色 RGB'),
    ('mosaic_terracotta_43deg','拼花与 N3 赤陶地砖 · 43°','实际地面网格与图集 / 原 N3 灯光与 ACES / 局部审阅，非整间开场')]:
    image=Image.open(OUT/'captures'/(name+'.png')).convert('RGB');w,h=image.size
    board=Image.new('RGB',(w,h+125),'#F7F6F2');board.paste(image,(0,70));draw=ImageDraw.Draw(board)
    draw.text((18,13),'SGODOT-323 / v1.2 / '+heading,font=title,fill='#55402E')
    draw.text((18,h+86),note,font=small,fill='#55402E');draw.text((w-138,h+86),'【黄忠】',font=small,fill='#55402E')
    path=DOC/(prefix+name+'.jpg');board.save(path,quality=95,subsampling=0,optimize=True);files.append(path)
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
    'instruction':'323 b31eaf83 / d5f8ef32','palette':json.loads((SRC/'mosaic_palette.json').read_text()),
    'revision':revision,'geometry':geometry,'source':source,'godot':godot,
    'floor_source':json.loads((OUT/'floor-source.json').read_text())}
path=DOC/(prefix+'validation.json');path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');files.append(path)
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,
    'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'author':'黄忠',
    'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in files],ensure_ascii=False,indent=2)+'\n')
print(DOC)
