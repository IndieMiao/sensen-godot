#!/usr/bin/env python3
"""Package inspected native Godot captures and measured review evidence. Requires Pillow/numpy."""
from pathlib import Path
import json,shutil,hashlib,colorsys
from PIL import Image,ImageDraw,ImageFont
import numpy as np
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/minehut-308';DOC=ROOT/'docs/design/mine-hut-308-2026-10-16';KIT=ROOT/'assets/rooms/mine_hut'
PREFIX='SGODOT-308_MINEHUT_v1_'
DOC.mkdir(parents=True,exist_ok=True)
for p in (OUT/'captures').glob('*.png'):shutil.copy2(p,DOC/(PREFIX+p.name))
for p in (OUT/'project/assets/rooms/mine_hut').glob('*.import'):shutil.copy2(p,KIT/p.name)
for rel in ['scenes/mine_hut/mine_hut_art.gd.uid']:
 p=OUT/'project'/rel
 if p.exists():shutil.copy2(p,ROOT/rel)
p=OUT/'project/review.gd.uid'
if p.exists():shutil.copy2(p,ROOT/'tools/art/review_mine_hut_308.gd.uid')
ref=Image.open(DOC/'reference.png').convert('RGB');run=Image.open(DOC/(PREFIX+'full_room_panorama.png')).convert('RGB')
patches=[('floor',(673,605),(609,537)),('upper timber',(1020,310),(940,299)),('cream plaster',(1010,347),(980,370)),('white hide',(650,655),(550,598))]
marked=[ref.copy(),run.copy()];colors=[]
for i,(name,a,b) in enumerate(patches,1):
 values=[];row={'surface':name}
 for k,im,xy in [('reference',ref,a),('runtime',run,b)]:
  x,y=xy;rgb=np.median(np.asarray(im)[y-5:y+6,x-5:x+6],axis=(0,1));h,s,v=colorsys.rgb_to_hsv(*(rgb/255));values.append(h*360)
  row[k]={'pixel':xy,'median_rgb':rgb.astype(int).tolist(),'hue_degrees':h*360,'saturation':s}
  d=ImageDraw.Draw(marked[0 if k=='reference' else 1]);d.rectangle([x-8,y-8,x+8,y+8],outline='#c40078',width=2);d.text((x+10,y-10),str(i),fill='#c40078')
 delta=abs(values[0]-values[1]);delta=min(delta,360-delta);row['hue_delta_degrees']=delta;row['passed']=bool(delta<=10);colors.append(row)
color={'method':'Declared 11x11 median patches on corresponding wood, plaster and white-hide surfaces; circular HSV hue difference <= 10 degrees. Not a whole-image fidelity metric. Stone/metal use the supplied grey-green farm-mine reference and neutral-metal brief. Brightness/saturation differences remain for art review.','patches':colors,'passed':all(c['passed'] for c in colors)}
(DOC/'colour-validation.json').write_text(json.dumps(color,indent=2)+'\n')
canvas=Image.new('RGB',(2454,1354),'#eee8de');canvas.paste(marked[0],(0,50));canvas.paste(marked[1],(1254,100))
d=ImageDraw.Draw(canvas);font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',24)
d.text((20,12),'STARK REFERENCE / SGODOT-308',font=font,fill='#514437');d.text((1280,12),'GODOT MOBILE / LIU BEI / 43 DEG',font=font,fill='#514437')
d.text((20,1312),' / '.join(c['surface']+': '+str(round(c['hue_delta_degrees'],2))+' deg' for c in colors),font=font,fill='#514437')
canvas.save(DOC/(PREFIX+'reference_comparison.png'))
geo=json.loads((OUT/'geometry-validation.json').read_text());godot=json.loads((OUT/'captures/godot-validation.json').read_text());stats=json.loads((KIT/'asset_stats.json').read_text())
assert not geo['failures'] and not godot['failures'];assert color['passed'],color
checks=len(geo['checks'])+len(godot['checks'])+len(colors)
layout=json.loads((KIT/'layout.json').read_text())
validation={'issue':'SGODOT-308','artist':'Liu Bei / 刘备','virtual_user_id':'0fb1de1f-ead5-443b-9537-54cbac113260','passed':True,'checks':checks,'geometry':geo,'godot':godot,'colour':color,'budget':stats,'suggested_anchors':layout['suggested_anchors'],'limits':['Desktop Vulkan Mobile, AMD Custom GPU 0405 / RADV VANGOGH; no connected Android target for this handoff, no phone performance claim.','Only Ivo and exit are interactive integration suggestions; no runtime anchors or gameplay data edited.','6.72 m native gameplay view deliberately preserves scale and crops room edges; separate 12.4 m panorama includes the complete room.','Art acceptance remains with Huowu; technical review with Shangguan Waner; merge requires user approval.']}
(DOC/'validation.json').write_text(json.dumps(validation,indent=2,ensure_ascii=False)+'\n')
manifest=[]
for p in sorted(DOC.glob(PREFIX+'*.png')):
 im=Image.open(p);manifest.append({'file':p.name,'size':list(im.size),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(DOC/'media-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('PACKAGED',len(manifest),'images;',checks,'checks;',stats['scene_triangles'],'triangles;',stats['static_draw_surfaces'],'surfaces')
