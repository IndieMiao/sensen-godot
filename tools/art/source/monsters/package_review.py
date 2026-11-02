"""Package inspected Godot captures without substituting Blender beauty renders."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[4]
parser=argparse.ArgumentParser();parser.add_argument('id');args=parser.parse_args()
OUT=ROOT/'output/monsters-355'/args.id
DOC=ROOT/'docs/design/monsters-355-2026-11-02'/args.id;DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-355_'+args.id+'_blockout_'
AUTHOR='5281cd25-6a49-4df8-9802-f3e534956e80'
spec=json.loads((ROOT/'output/monsters-355/runtime/assets/monsters'/args.id/(args.id+'.json')).read_text())
geometry=json.loads((OUT/'geometry-validation.json').read_text());godot=json.loads((OUT/'captures/godot-validation.json').read_text())
assert geometry['passed'] and godot['passed']
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
font=lambda size:ImageFont.truetype(FONT,size)
files=[]

def write(name,image):
    p=DOC/(PREFIX+name+'.png');image.save(p);files.append(p)

def footer(draw,size):
    draw.text((16,size[1]-28),'【黄忠】 SGODOT-355 / '+args.id+' / 灰模 / Godot Mobile',font=font(16),fill='#415650')

three=Image.new('RGB',(1440,610),'#edf2ef');draw=ImageDraw.Draw(three)
draw.text((16,10),args.id+' / 三视图',font=font(24),fill='#30463f')
draw.text((16,45),str(spec['triangles'])+' 三角形 / '+str(spec['bones'])+' 骨 / 1 surface；高度 '+f"{spec['height']:.3f}"+' m，正面 +Z',font=font(18),fill='#52675f')
for i,(name,title) in enumerate([('front','正面'),('side','右侧'),('back','背面')]):
    three.paste(Image.open(OUT/'captures'/(name+'.png')).convert('RGB'),(i*480,100))
    draw.text((i*480+16,75),title,font=font(18),fill='#30463f')
footer(draw,three.size);write('three_views',three)
columns=4;rows=(len(spec['anims'])+columns-1)//columns
sheet=Image.new('RGB',(1440,rows*390+120),'#edf2ef');draw=ImageDraw.Draw(sheet)
draw.text((16,10),args.id+' / 全动作关键帧',font=font(24),fill='#30463f')
for i,(name,anim) in enumerate(spec['anims'].items()):
    x=(i%columns)*360;y=55+(i//columns)*390
    info=name+' / '+str(anim['length'])+'s'+(' loop' if anim.get('loop') else '')
    if 'hit_at' in anim:info+=' / hit '+str(anim['hit_at'])
    if 'emit_at' in anim:info+=' / emit '+str(anim['emit_at'])
    draw.text((x+10,y),info,font=font(16),fill='#30463f')
    image=Image.open(OUT/'captures'/('action_'+name+'.png')).convert('RGB').resize((360,360),Image.Resampling.LANCZOS)
    sheet.paste(image,(x,y+27))
footer(draw,sheet.size);write('animation_keys',sheet)
capture=Image.open(OUT/'captures/mine_default_43deg.png').convert('RGB')
mine=Image.new('RGB',(360,900),'#edf2ef');mine.paste(capture,(0,68));draw=ImageDraw.Draw(mine)
draw.text((12,8),'灰模 / 矿内默认 43°',font=font(17),fill='#30463f')
draw.text((12,39),'玩家 1.745 m / 史莱姆 r=0.40 m',font=font(12),fill='#52675f')
draw.text((12,877),'【黄忠】 SGODOT-355 / Godot Mobile',font=font(12),fill='#415650');write('mine_default_43deg',mine)
record=DOC/(PREFIX+'validation.json')
record.write_text(json.dumps({'author':'黄忠','virtual_user_id':AUTHOR,'passed':True,'geometry':geometry,'godot':godot},ensure_ascii=False,indent=2)+'\n');files.append(record)
(DOC/(PREFIX+'media-manifest.json')).write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,
    'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'virtual_user_id':AUTHOR} for p in files],indent=2)+'\n')
print(DOC)
