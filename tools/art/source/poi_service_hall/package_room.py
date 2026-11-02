"""Signed, unscaled Godot review captures for the complete N2 room."""
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont
from dependencies import ROOT,OUT,write_json

DOC=ROOT/'docs/design/poi-service-hall-321-room-2026-11-02'
DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-321_N2_v1_room_'
AUTHOR='5281cd25-6a49-4df8-9802-f3e534956e80'
font='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
records={name:json.loads((OUT/path).read_text()) for name,path in [
    ('geometry','room-geometry-validation.json'),('godot','room_captures/godot-validation.json')]}
assert all(record['passed'] for record in records.values())
files=[]
for name,title,subtitle in [
    ('default_43deg_360','N2 服务大厅 / B 方案 · 8 座','43° / 6.72 m / 360px；人物 1.745 m'),
    ('overview','N2 服务大厅 / 整间全景','53,892 三角形 / 34 surface；单张 2048² 图集；雕塑高 1.60 m'),
    ('top_capsule','N2 服务大厅 / 正俯视与胶囊扫掠','蓝圈：16 站位；金圈：8 座；绿线：座位接近路线；红线：环道最窄 1.04 m')]:
    source=Image.open(OUT/'room_captures'/(name+'.png')).convert('RGB')
    image=Image.new('RGB',(source.width,source.height+106),'#eef2f0');image.paste(source,(0,72))
    draw=ImageDraw.Draw(image);size=16 if source.width<500 else 24
    draw.text((14,8),title,font=ImageFont.truetype(font,size),fill='#354740')
    draw.text((14,39),subtitle,font=ImageFont.truetype(font,12 if source.width<500 else 17),fill='#53635d')
    draw.text((14,image.height-26),'【黄忠】 SGODOT-321 / Godot Mobile / v1 room',font=ImageFont.truetype(font,12 if source.width<500 else 17),fill='#53635d')
    path=DOC/(PREFIX+name+'.png');image.save(path);files.append(path)
record=DOC/(PREFIX+'validation.json')
write_json(record,{'author':'黄忠','virtual_user_id':AUTHOR,'passed':True,**records});files.append(record)
write_json(DOC/(PREFIX+'media-manifest.json'),[{'file':p.name,'bytes':p.stat().st_size,
    'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'virtual_user_id':AUTHOR} for p in files])
print(DOC)
