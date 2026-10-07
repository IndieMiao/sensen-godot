"""Declared corresponding-surface patch measurements, independent of rendering."""
from pathlib import Path
import json,sys,colorsys
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];slug=sys.argv[1];rev=sys.argv[2] if len(sys.argv)>2 else 'r1';doc=ROOT/'docs/design'/(slug+'-2026-10-07');out=ROOT/'output'/slug/rev
spec=json.loads((doc/'colour-samples.json').read_text());ref=Image.open(doc/'reference.png').convert('RGB');run=Image.open(out/'godot-whole.png').convert('RGB');marked=[ref.copy(),run.copy()];checks=[]
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',21)
for i,s in enumerate(spec):
 rec=dict(s);hues=[]
 for j,(label,im) in enumerate([('reference',ref),('runtime',run)]):
  x,y=s[label+'_pixel'];rgb=np.median(np.array(im)[y-4:y+5,x-4:x+5],axis=(0,1));h,sat,val=colorsys.rgb_to_hsv(*(rgb/255));hues.append(h*360);rec[label]={'rgb':rgb.astype(int).tolist(),'hex':'#'+''.join(f'{int(c):02X}' for c in rgb),'hue_degrees':round(h*360,3),'saturation':round(sat,4),'value':round(val,4)}
  d=ImageDraw.Draw(marked[j]);d.rectangle((x-8,y-8,x+8,y+8),outline='#d52950',width=3);d.text((x+10,y),str(i+1),font=font,fill='#d52950')
 delta=abs(hues[1]-hues[0]);delta=min(delta,360-delta);rec.update(hue_delta_degrees=round(delta,3),passed=bool(delta<=10));checks.append(rec)
can=Image.new('RGB',(1800,1040),'#eee7df');draw=ImageDraw.Draw(can)
for j,im in enumerate(marked):
 im.thumbnail((900,900));can.paste(im,(900*j+(900-im.width)//2,50+(900-im.height)//2));draw.text((j*900+20,15),['Reference surfaces','Runtime corresponding surfaces'][j],font=font,fill='#443b37')
for i,c in enumerate(checks):draw.text((20+(i%3)*585,955+(i//3)*30),f"{i+1} {c['name']}: {c['hue_delta_degrees']:.2f} deg",font=font,fill='#443b37')
can.save(doc/'colour-patch-comparison.jpg',quality=94)
result={'revision':rev,'method':'9x9 median RGB, HSV circular hue difference; same authored physical surfaces; no pixel registration','checks':checks,'passed':all(c['passed'] for c in checks),'limits':'Representative lit patches only, not a complete-image fidelity score; brightness/saturation retained for review.'};(doc/'colour-verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));assert result['passed']
