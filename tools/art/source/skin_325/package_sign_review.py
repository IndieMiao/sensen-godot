"""Package the inset-sign runtime-text proof requested for SGODOT-325 v1.2."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/skin-325-v1'
DOC=ROOT/'docs/design/skin-325-B-2026-11-03/v1.2';DOC.mkdir(parents=True,exist_ok=True)
godot=json.loads((OUT/'captures-v1.2/godot-validation.json').read_text())
source=json.loads((OUT/'preservation-validation.json').read_text())
assert godot['passed'] and source['passed']
assert 'ERROR:' not in (OUT/'render-v1.2.log').read_text()
image=Image.open(OUT/'captures-v1.2/N2_sign_Service_Hall.png').convert('RGB')
assert image.size==(1600,800)
board=Image.new('RGB',(1600,920),'#F5F6F5');board.paste(image,(0,70));draw=ImageDraw.Draw(board)
font='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
title=ImageFont.truetype(font,30);small=ImageFont.truetype(font,23)
draw.text((18,15),'SGODOT-325 / N2 B v1.2 / Service Hall 运行时文字近景',font=title,fill='#263E42')
draw.text((18,882),'贴片 0.88 × 0.23 m 收进木框 / 写字区 0.66 m、向右偏 0.10 m / PNG 不烤字',font=small,fill='#34494B')
draw.text((1450,882),'【黄忠】',font=small,fill='#34494B')
prefix='SGODOT-325_skin_B_v1.2_';path=DOC/(prefix+'N2_sign_Service_Hall.jpg')
board.save(path,quality=95,subsampling=0,optimize=True);files=[path]
path=DOC/(prefix+'validation.json')
path.write_text(json.dumps({'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
    'instruction':'325 db90ab66','godot':godot,'preservation':source},ensure_ascii=False,indent=2)+'\n');files.append(path)
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,
    'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'author':'黄忠',
    'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in files],ensure_ascii=False,indent=2)+'\n')
print(DOC)
