"""Package signed mine-module captures without resizing the game viewport."""
from pathlib import Path
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'output/mine-kit-355/mine_props'
DOC=ROOT/'docs/design/mine-kit-355-2026-11-02/mine_props'
DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-355_mine_props_v1_'
font=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',20)
small=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',17)
media=[]

def record(path):
    media.append({'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'})

def sheet(keys,name,title,labels,footer):
    images=[Image.open(OUT/'captures'/(key+'.png')).convert('RGB') for key in keys]
    width=sum(im.width for im in images);height=max(im.height for im in images)
    out=Image.new('RGB',(width,height+140),'#F1F4F3');draw=ImageDraw.Draw(out)
    draw.text((14,9),title,font=font,fill='#23352E');x=0
    for image,label in zip(images,labels):
        draw.text((x+14,39),label,font=small,fill='#23352E');out.paste(image,(x,70));x+=image.width
    draw.text((14,height+80),footer,font=small,fill='#23352E')
    draw.text((width-103,height+108),'【黄忠】',font=small,fill='#23352E')
    path=DOC/(PREFIX+name+'.png');out.save(path);record(path)

glb=json.loads((OUT/'glb-validation.json').read_text());godot=json.loads((OUT/'captures/godot-validation.json').read_text())
assert glb['passed'] and godot['passed']
for kind,label in [('arena','Guard arena'),('elevator','Elevator station')]:
    sheet([f'{mine}_{kind}_default_43deg' for mine in ['red','purple']],kind+'_two_mines_43deg',
        'SGODOT-355 / '+label+' / v1',['Red-rock mine','Purple-grey mine'],
        '43 deg / each 360 x 800 / game zoom .8 / player H=1.745 m')
for mine,label in [('red','Red-rock mine'),('purple','Purple-grey mine')]:
    sheet([mine+'_both_props_43deg'],mine+'_both_props_43deg','SGODOT-355 / Coexisting modules / v1',
        [label+' / overview at 43 deg'],'Arena 2,421 tris / station 2,394 tris / one surface each / no collision')
sheet(['red_four_ores_43deg','purple_four_ores_43deg'],'four_ores_two_mines_43deg','SGODOT-355 / Ore rocks / v1',
    ['Red: iron / quartz / coal / copper','Purple-grey: iron / quartz / coal / copper'],
    'Same four-tier seven-sided rock family / each radius <= .47 m / height about .63 m / vertex paint')
sheet(['elevator_detail'],'elevator_detail','SGODOT-355 / Elevator / v1',['Blank plate and hoist'],
    '2,394 tris / H=2.24 m / platform Y=.17 m')
manifest={key:json.loads((ROOT/'output/monsters-355/runtime/assets/mine'/key/'manifest.json').read_text()) for key in ['rocks','props']}
path=DOC/(PREFIX+'validation.json');path.write_text(json.dumps({'author':'黄忠',
    'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','manifest':manifest,'glb':glb,'godot':godot,
    'dependencies':json.loads((OUT/'dependencies.json').read_text())},ensure_ascii=False,indent=2)+'\n');record(path)
(DOC/(PREFIX+'media-manifest.json')).write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print(DOC,len(media),'attachments')
