"""Fixed corresponding surface samples, not an image-fidelity score."""
from pathlib import Path
import json,colorsys
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4]
DOC=ROOT/'docs/design/standard_room_5-review21-2026-10-07'
OUT=ROOT/'output/zhaoyun-r21-2026-10-07'
reference=Image.open(DOC/'reference.png').convert('RGB')
runtime=Image.open(OUT/'godot.png').convert('RGB')
# Locations are specified on a 960x720 planning canvas, then mapped to each
# full-resolution image. Face identity, not equality of screen pixel, is used.
patches=[
 ('left_plaster',(210,248),(236,250),'Left wall plaster between botanical picture and arched window'),
 ('back_plaster',(699,246),(702,250),'Back wall plaster above-left of the green doorway'),
 ('front_pillar',(146,293),(159,299),'Front-left timber post, bright interior-facing flat strip'),
 ('sunlit_floor',(657,497),(650,500),'Clear wood floor to the right of the dining rug'),
]
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',19)
marked=[reference.copy(),runtime.copy()];checks=[]
for number,(name,a,b,description) in enumerate(patches,1):
 record={'name':name,'surface':description,'patch_size':11};hues=[]
 for index,(label,im,point) in enumerate([('reference',reference,a),('runtime',runtime,b)]):
  x=round(point[0]*im.width/960);y=round(point[1]*im.height/720)
  rgb=np.median(np.asarray(im)[y-5:y+6,x-5:x+6],axis=(0,1));h,s,v=colorsys.rgb_to_hsv(*(rgb/255));h*=360;hues.append(h)
  record[label]={'pixel':[x,y],'rgb':rgb.astype(int).tolist(),'hex':'#'+''.join(f'{int(c):02X}' for c in rgb),'hue_degrees':round(h,3),'saturation':round(s,4),'value':round(v,4)}
  draw=ImageDraw.Draw(marked[index]);draw.rectangle((x-11,y-11,x+11,y+11),outline='#d02066',width=3);draw.text((x+14,y-10),str(number),font=font,fill='#d02066')
 delta=abs(hues[0]-hues[1]);delta=min(delta,360-delta);record.update(hue_delta_degrees=round(delta,3),limit_degrees=10,passed=bool(delta<=10));checks.append(record)
canvas=Image.new('RGB',(1920,840),'#f5f0df');draw=ImageDraw.Draw(canvas)
for i,(label,im) in enumerate(zip(['Reference / fixed surface samples','R2.1 / corresponding surface samples'],marked)):
 im=im.resize((960,720),Image.Resampling.LANCZOS);canvas.paste(im,(i*960,52));draw.text((i*960+18,15),label,font=font,fill='#53462f')
draw.text((20,792),'   '.join(f'{i+1}: {c["hue_delta_degrees"]:.2f} deg' for i,c in enumerate(checks))+'   | limit <=10 deg',font=font,fill='#53462f')
canvas.save(DOC/'colour-samples.png')
result={'method':'11x11 median RGB; circular HSV hue distance; fixed corresponding authored surfaces','checks':checks,'passed':all(c['passed'] for c in checks),'limits':'These explicit lit patches only; saturation and brightness are separately reported. No full-image fidelity or pixel registration claim.'}
(DOC/'colour-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2));assert result['passed']
