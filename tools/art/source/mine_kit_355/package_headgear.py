"""Create signed review sheets from unmodified Godot captures."""
from pathlib import Path
import hashlib
import json
import argparse
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'output/mine-kit-355/headgear'
parser=argparse.ArgumentParser();parser.add_argument('--stage',default='v1.1');args=parser.parse_args()
DOC=ROOT/'docs/design/mine-kit-355-2026-11-02/headgear'
if args.stage!='v1':DOC=DOC/args.stage
DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-355_slime_king_'+args.stage+'_'
manifest=json.loads((ROOT/'tools/art/source/monsters/slime_king/manifest.json').read_text())
godot=json.loads((OUT/'captures/godot-validation.json').read_text())
glb=json.loads((OUT/'glb-validation.json').read_text())
assert godot['passed'] and glb['passed']
fontpath='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
font=ImageFont.truetype(fontpath,20);small=ImageFont.truetype(fontpath,17)
media=[]

def record(path):
    media.append({'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'})

def sheet(spec,views,suffix,subtitle):
    width=512*len(views)
    image=Image.new('RGB',(width,650),'#F1F4F3');draw=ImageDraw.Draw(image)
    draw.text((16,10),'SGODOT-355 / '+spec['name']+' / '+args.stage,font=font,fill='#23352E')
    draw.text((16,40),subtitle,font=small,fill='#42574E')
    for i,(view,label) in enumerate(views):
        source=Image.open(OUT/'captures'/(spec['name']+'_'+view+'.png')).convert('RGB')
        assert source.size==(512,512)
        image.paste(source,(i*512,74));draw.text((i*512+16,80),label,font=small,fill='#334B40')
    size=' x '.join(f'{v:.3f}' for v in spec['dimensions_m'])
    footer=f"{spec['triangles']} tris | 1 surface | {size} m"
    if width>512:footer+=' | Godot 4.7.2 Vulkan Mobile'
    draw.text((16,591),footer,font=small,fill='#23352E')
    draw.text((width-103,610),'【黄忠】',font=small,fill='#23352E')
    path=DOC/(PREFIX+spec['name']+'_'+suffix+'.png');image.save(path);record(path)

for spec in manifest['assets']:
    sheet(spec,[('front','Front +Z'),('side','Side +X'),('back','Back -Z')],
        'three_views','Orthographic model views / local origin at head contact centre')
    views=[('mounted_43deg','43 deg / front')]
    if spec['name']=='ironback_plates':views.append(('mounted_rear','43 deg / rear'))
    sheet(spec,views,'mounted_43deg','r = 1.0 m / attach Y = 1.43 m / body tint proposal')
    pair=Image.new('RGB',(720,934),'#F1F4F3');draw=ImageDraw.Draw(pair)
    draw.text((14,9),'SGODOT-355 / '+spec['name']+' / '+args.stage,font=font,fill='#23352E')
    for i,(key,label) in enumerate([('red','Red-rock mine'),('purple','Purple-grey mine')]):
        source=Image.open(OUT/'captures'/(spec['name']+'_'+key+'_mine_43deg.png')).convert('RGB')
        assert source.size==(360,800)
        pair.paste(source,(360*i,68));draw.text((360*i+14,38),label,font=small,fill='#23352E')
    draw.text((14,875),'43 deg / 360 x 800 each / r=1.0 m / player H=1.745 m',font=small,fill='#23352E')
    draw.text((615,891),'【黄忠】',font=small,fill='#23352E')
    path=DOC/(PREFIX+spec['name']+'_two_mines_43deg.png');pair.save(path);record(path)

path=DOC/(PREFIX+'validation.json')
path.write_text(json.dumps({'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
    'manifest':manifest,'glb':glb,'godot':godot,
    'dependencies':json.loads((OUT/'dependencies.json').read_text())},ensure_ascii=False,indent=2)+'\n');record(path)
(DOC/(PREFIX+'media-manifest.json')).write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print(DOC,len(media),'review attachments')
