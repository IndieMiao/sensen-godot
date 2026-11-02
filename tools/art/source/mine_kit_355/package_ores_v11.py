"""One side-by-side two-mine comparison for the vertex-colour revision."""
from pathlib import Path
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'output/mine-kit-355/mine_props'
DOC=ROOT/'docs/design/mine-kit-355-2026-11-02/mine_props/v1.1'
DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-355_mine_props_v1.1_'
font=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',20)
small=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',17)
godot=json.loads((OUT/'captures/godot-validation.json').read_text())
glb=json.loads((OUT/'glb-validation.json').read_text())
assert godot['passed'] and glb['passed']
out=Image.new('RGB',(1800,640),'#F1F4F3');draw=ImageDraw.Draw(out)
draw.text((14,10),'SGODOT-355 / Ore colours v1.1 / 43 deg',font=font,fill='#23352E')
for i,(key,label) in enumerate([('red','Red-rock mine'),('purple','Purple-grey mine')]):
    source=Image.open(OUT/'captures'/(key+'_four_ores_43deg.png')).convert('RGB');assert source.size==(900,500)
    out.paste(source,(900*i,70));draw.text((900*i+14,39),label+' / iron / quartz / coal / copper',font=small,fill='#23352E')
draw.text((14,584),'Vertex colours only / each 114 tris, 1 surface / geometry, normals and UIDs retained / player H=1.745 m',font=small,fill='#23352E')
draw.text((1690,612),'【黄忠】',font=small,fill='#23352E')
path=DOC/(PREFIX+'four_ores_two_mines_43deg.png');out.save(path);paths=[path]
path=DOC/(PREFIX+'validation.json');path.write_text(json.dumps({'author':'黄忠',
    'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','manifest':json.loads((ROOT/'output/monsters-355/runtime/assets/mine/rocks/manifest.json').read_text()),
    'glb':glb,'godot':godot,'dependencies':json.loads((OUT/'dependencies.json').read_text())},ensure_ascii=False,indent=2)+'\n');paths.append(path)
media=[{'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'author':'黄忠',
    'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in paths]
(DOC/(PREFIX+'media-manifest.json')).write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print(DOC,len(media),'attachments')
