"""Package the seven-item white sheet and player-scale screenshot without rescaling models."""
from pathlib import Path
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
OUT=ROOT/'output/classroom-props-322';CAP=OUT/'captures'
DOC=ROOT/'docs/design/classroom-props-322-2026-11-03';DOC.mkdir(parents=True,exist_ok=True)
KIT=ROOT/'assets/rooms/poi_classroom/props';manifest=json.loads((KIT/'prop_manifest.json').read_text())
geometry=json.loads((OUT/'geometry-validation.json').read_text());godot=json.loads((CAP/'godot-validation.json').read_text())
source=json.loads((OUT/'source-validation.json').read_text())
assert geometry['passed'] and godot['passed'] and source['passed']
for name in ['import.log','render.log']:assert 'ERROR:' not in (OUT/name).read_text()
for spec in manifest['assets']:
    assert (KIT/spec['file']).read_bytes()==(OUT/'project/assets/rooms/poi_classroom/props'/spec['file']).read_bytes()
font='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
title=ImageFont.truetype(font,30);label=ImageFont.truetype(font,23);small=ImageFont.truetype(font,19)
names={'blackboard':'黑板','teacher_desk':'讲台','globe':'地球仪','desk_stationery':'书本 + 笔筒',
    'plaster_study':'石膏头像 + 几何体','reading_cushion':'阅读软垫','name_sign':'空白招牌'}
sheet=Image.new('RGB',(2800,800),'white');draw=ImageDraw.Draw(sheet)
draw.text((24,15),'SGODOT-322 / N4 props v1 / 七件独立道具',font=title,fill='#263A43')
draw.text((2280,20),'制作：黄忠 / 317 R3',font=label,fill='#263A43')
for i,spec in enumerate(manifest['assets']):
    image=Image.open(CAP/(spec['name']+'.png')).convert('RGB');assert image.size==(400,600)
    sheet.paste(image,(i*400,68))
    dim=geometry['assets'][spec['name']]['dimensions_m']
    text=spec['module']+' '+names[spec['name']]+(' x2' if spec['quantity']==2 else '')
    draw.text((i*400+15,663),text,font=label,fill='#263A43')
    draw.text((i*400+15,705),' x '.join(f'{v:.3f}' for v in dim)+' m',font=small,fill='#3D515B')
    draw.text((i*400+15,738),str(spec['triangles'])+' tris | 1 surface',font=small,fill='#3D515B')
draw.text((24,773),'W x H x D；各件独立取景，尺寸以实测标注为准。总计：'+str(geometry['unique_triangles'])+' unique / '+str(geometry['placed_triangles'])+' placed tris',font=small,fill='#3D515B')
prefix='SGODOT-322_props_v1_';row=DOC/(prefix+'lineup.jpg');sheet.save(row,quality=95,subsampling=0,optimize=True)
image=Image.open(CAP/'scale_43deg.png').convert('RGB');assert image.size==(1600,1450)
scale=Image.new('RGB',(1600,1540),'white');scale.paste(image,(0,60));sd=ImageDraw.Draw(scale)
sd.text((24,12),'SGODOT-322 / N4 props v1 / 43 deg / Player H = 1.745 m',font=title,fill='#263A43')
sd.text((24,1502),'讲台桌面 1.134 m；白色支撑体仅作比例示意，不是房间布置。',font=label,fill='#3D515B')
sd.text((1400,1502),'【黄忠】',font=label,fill='#263A43')
scale_path=DOC/(prefix+'scale_43deg.jpg');scale.save(scale_path,quality=95,subsampling=0,optimize=True)
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','geometry':geometry,'godot':godot,'source':source,'manifest':manifest,
    'source_sha256':hashlib.sha256((SRC/'classroom_props.blend').read_bytes()).hexdigest()}
validation=DOC/(prefix+'validation.json');validation.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
media=[{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
    'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in [row,scale_path,validation]]
(DOC/'media-manifest.json').write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(media,ensure_ascii=False,indent=2))
