"""Measure declared, fixed corresponding lit patches. Never searches for a match."""
from pathlib import Path
import sys,json,colorsys,os
from PIL import Image,ImageDraw,ImageFont,ImageOps
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
slug=sys.argv[1];doc=ROOT/'docs/design'/(slug+'-2026-10-07');out=Path(os.environ.get('SCENE_REVIEW_OUTPUT',ROOT/'output'/('zhaoyun-'+sys.argv[2]+'-review-2026-10-07')))
spec=json.loads((ROOT/'tools/art/source'/slug/'colour-patches.json').read_text())
ims=[Image.open(doc/'reference.png').convert('RGB'),Image.open(out/'godot.png').convert('RGB')]
# Coordinates are normalized to a 1440x1080 contained canvas (no stretching).
ims=[ImageOps.pad(im,(1440,1080),color='#f5f0df') for im in ims];marked=[im.copy() for im in ims];results=[]
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',22)
for n,s in enumerate(spec['patches'],1):
 result={'name':s['name'],'surface':s['surface'],'patch_size':11};hues=[]
 for i,key in enumerate(('reference','runtime')):
  x,y=s[key];rgb=np.median(np.asarray(ims[i])[y-5:y+6,x-5:x+6],axis=(0,1));h,ss,v=colorsys.rgb_to_hsv(*(rgb/255));h*=360;hues.append(h)
  result[key]={'pixel':[x,y],'rgb':rgb.astype(int).tolist(),'hex':'#'+''.join(f'{int(c):02X}' for c in rgb),'hue_degrees':round(h,3),'saturation':round(ss,4),'value':round(v,4)}
  d=ImageDraw.Draw(marked[i]);d.rectangle((x-10,y-10,x+10,y+10),outline='#d02066',width=3);d.text((x+14,y-12),str(n),font=font,fill='#d02066')
 delta=abs(hues[0]-hues[1]);delta=min(delta,360-delta);result.update(hue_delta_degrees=round(delta,3),limit_degrees=10,passed=bool(delta<=10));results.append(result)
canvas=Image.new('RGB',(1920,815),'#f5f0df');d=ImageDraw.Draw(canvas)
for i,im in enumerate(marked):canvas.paste(im.resize((960,720),Image.Resampling.LANCZOS),(i*960,50));d.text((i*960+20,12),['Reference / declared locations','Runtime / corresponding locations'][i],font=font,fill='#53462f')
d.text((18,779),' | '.join(f'{r["name"]}: {r["hue_delta_degrees"]:.2f} deg' for r in results),font=font,fill='#53462f');canvas.save(doc/'colour-samples.png')
result={'method':'11x11 RGB median; circular HSV hue distance; fixed declared corresponding lit faces','checks':results,'passed':all(r['passed'] for r in results),'limits':'Representative patches only. Full image retains independent brightness/saturation/composition differences.'}
(doc/'colour-verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));assert result['passed']
