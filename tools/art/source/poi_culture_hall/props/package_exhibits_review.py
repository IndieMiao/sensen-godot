"""Package the enlarged exhibits at the same 43-degree camera and two close-ups."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4];OUT=ROOT/'output/culture-props-323'
DOC=ROOT/'docs/design/poi-culture-props-323-2026-11-03/v1.1';DOC.mkdir(parents=True,exist_ok=True)
reports={key:json.loads((OUT/path).read_text()) for key,path in [
    ('geometry','geometry-validation.json'),('source','source-validation.json'),
    ('revision','exhibits-revision-validation.json'),('godot','captures-v1.1/godot-validation.json')]}
assert all(v['passed'] for v in reports.values())
assert 'ERROR:' not in (OUT/'render-v1.1.log').read_text()
old_report=json.loads((OUT/'captures/godot-validation.json').read_text())
old_camera=next(c for c in old_report['captures'] if c['id']=='scale_43deg')
new_camera=next(c for c in reports['godot']['captures'] if c['id']=='scale_43deg')
assert old_camera==new_camera
prefix='SGODOT-323_props_v1.1_';files=[]
font='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
title=ImageFont.truetype(font,36);label=ImageFont.truetype(font,30);small=ImageFont.truetype(font,26)
board=Image.new('RGB',(3632,1950),'white');draw=ImageDraw.Draw(board)
draw.text((24,12),'SGODOT-323 / 两柜展品组 v1.1 / 1.4 倍展品 + 0.06 m 浅色托座 / 43° 同机位',font=title,fill='#283D34')
for x,folder,caption in [(0,'captures','v1'),(1832,'captures-v1.1','v1.1')]:
    image=Image.open(OUT/folder/'scale_43deg.png').convert('RGB');assert image.size==(1800,1800)
    board.paste(image,(x,100));draw.text((x+24,62),caption,font=label,fill='#283D34')
draw.text((24,1910),'原点、外部摆放、柜体与其他模型保持 / 摆放 6,140 面、11 surface / 玩家 H=1.745 m',font=small,fill='#3C5146')
draw.text((3465,1910),'【黄忠】',font=small,fill='#283D34')
path=DOC/(prefix+'scale_compare_43deg.jpg');board.save(path,quality=94,subsampling=0,optimize=True);files.append(path)
board=Image.new('RGB',(2032,1130),'white');draw=ImageDraw.Draw(board)
draw.text((24,12),'SGODOT-323 / v1.1 玻璃柜内展品近景',font=title,fill='#283D34')
for x,name in [(0,'cabinet_glass_detail'),(1032,'cabinet_2_glass_detail')]:
    image=Image.open(OUT/'captures-v1.1'/(name+'.png')).convert('RGB');assert image.size==(1000,1000)
    board.paste(image,(x,75))
draw.text((24,1090),'三个展示位/柜不变；展品落在托座上，托座接触柜面，无穿玻璃。',font=small,fill='#3C5146')
draw.text((1865,1090),'【黄忠】',font=small,fill='#283D34')
path=DOC/(prefix+'case_details.jpg');board.save(path,quality=94,subsampling=0,optimize=True);files.append(path)
manifest=json.loads((ROOT/'assets/rooms/poi_culture_hall/props/prop_manifest.json').read_text())
path=DOC/(prefix+'validation.json');path.write_text(json.dumps({'author':'黄忠',
    'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','instruction':'323 8d679529',
    'same_camera':True,'manifest':manifest,**reports},ensure_ascii=False,indent=2)+'\n');files.append(path)
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,
    'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'author':'黄忠',
    'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in files],ensure_ascii=False,indent=2)+'\n')
print(DOC)
