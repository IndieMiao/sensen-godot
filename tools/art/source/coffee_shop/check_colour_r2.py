"""Compare fixed, annotated semantic surface patches in source and runtime images.
These are same physical surfaces, not identical screen coordinates or a fidelity score.
"""
from pathlib import Path
import json,colorsys,sys
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];doc=ROOT/'docs/design/coffee_shop-2026-10-07';out=ROOT/'output/coffee_shop'/(sys.argv[1] if len(sys.argv)>1 else 'r2')
ref=Image.open(doc/'reference.png').convert('RGB');run=Image.open(out/'godot-whole.png').convert('RGB')
patches=[('front_right_pillar_lit',(831,1333),(775,1128),'Front-right corner pier; outward lit face'),('front_floor_lit',(606,1050),(493,911),'Unobstructed front floor between the left table and entrance'),('right_low_wall_lit',(1160,1150),(1045,982),'Right low-wall sage boarding; outward lit face')]
checks=[]
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',18)
for i,(name,a,b,description) in enumerate(patches):
 record={'name':name,'surface':description,'reference_pixel':a,'runtime_pixel':b,'patch_size':9};hues=[]
 for label,im,(x,y) in [('reference',ref,a),('runtime',run,b)]:
  # Read from fresh image so labels never contaminate a later sample.
  raw=Image.open(doc/'reference.png' if label=='reference' else out/'godot-whole.png').convert('RGB')
  rgb=np.median(np.asarray(raw)[y-4:y+5,x-4:x+5],axis=(0,1));h,s,v=colorsys.rgb_to_hsv(*(rgb/255));hues.append(h*360)
  record[label]={'rgb':rgb.astype(int).tolist(),'hex':'#'+''.join(f'{int(c):02X}' for c in rgb),'hue_degrees':round(h*360,3),'saturation':round(s,4),'value':round(v,4)}
  d=ImageDraw.Draw(im);d.rectangle((x-8,y-8,x+8,y+8),outline='#cf3050',width=3);d.text((x-42,y+13),str(i+1),fill='#cf3050',font=font)
 delta=abs(hues[0]-hues[1]);delta=min(delta,360-delta);record.update(hue_delta_degrees=round(delta,3),limit_degrees=10,passed=bool(delta<=10));checks.append(record)
canvas=Image.new('RGB',(1800,990),'#f4f1e6');d=ImageDraw.Draw(canvas)
for i,(im,label) in enumerate(((ref,'Reference | numbered physical surface patches'),(run,out.name.upper()+' runtime | same physical surfaces'))):
 im.thumbnail((900,900));canvas.paste(im,(i*900+(900-im.width)//2,50+(900-im.height)//2));d.text((i*900+20,12),label,font=font,fill='#4b4536')
d.text((20,955),'1 pillar: %.2f deg   2 floor: %.2f deg   3 wall: %.2f deg  |  limit <= 10 deg'%tuple(r['hue_delta_degrees'] for r in checks),font=font,fill='#4b4536')
canvas.save(doc/'colour-patch-comparison.jpg',quality=95)
result={'revision':'R2.1' if out.name=='r21' else 'R2','method':'9x9 RGB median; HSV circular hue distance; corresponding authored surface positions, not same screen pixel','correction':'R1 limestone sample (1229,674) was a wooden window mullion, not limestone. R1 honey_oak (606,1020) overlapped the rug edge. R2 labels and fresh physical-surface coordinates supersede those claims.','checks':checks,'passed':all(c['passed'] for c in checks),'limits':'Only these declared representative lit patches are measured. This does not establish full-image colour or reference fidelity; brightness/saturation are recorded separately.'}
(doc/'colour-verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));assert result['passed']
