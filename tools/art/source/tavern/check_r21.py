"""177 R2.1: fixed corresponding lit wall/floor samples and R2 brightness controls."""
from pathlib import Path
import json, colorsys, io, subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[4]
doc=ROOT/'docs/design/tavern-2026-10-07';out=ROOT/'output/tavern/r21'
spec=[{'name':'Left wall above sconce, beside stag flag','reference_pixel':[163,571],'runtime_pixel':[138,531]},
      {'name':'Front-right floor plank','reference_pixel':[969,1050],'runtime_pixel':[945,1065]}]
images=[Image.open(doc/'reference.png').convert('RGB'),Image.open(io.BytesIO(subprocess.check_output(['git','show','dffe008f:docs/design/tavern-2026-10-07/godot-whole.png'],cwd=ROOT))).convert('RGB'),Image.open(out/'godot-whole.png').convert('RGB')]
def measure(im,xy):
 x,y=xy;c=np.median(np.asarray(im)[y-4:y+5,x-4:x+5],axis=(0,1));s=c/255
 linear=np.where(s<=.04045,s/12.92,((s+.055)/1.055)**2.4);Y=linear @ np.array([.2126,.7152,.0722])
 L=116*np.cbrt(Y)-16 if Y>(6/29)**3 else Y*(29/3)**3
 h,sat,v=colorsys.rgb_to_hsv(*(c/255))
 return {'rgb':c.astype(int).tolist(),'hue_degrees':h*360,'HSV_value':v,'Lab_Lstar':float(L)}
checks=[]
for rec in spec:
 for label,im in zip(['reference','R2','R2.1'],images):rec[label]=measure(im,rec['reference_pixel' if label=='reference' else 'runtime_pixel'])
 a,b=rec['reference'],rec['R2.1'];dh=abs(a['hue_degrees']-b['hue_degrees']);dh=min(dh,360-dh)
 rec['hue_delta_degrees']=round(dh,3)
 for metric in ['HSV_value','Lab_Lstar']:rec[metric+'_relative_difference_percent']=round(abs(b[metric]-a[metric])/a[metric]*100,3)
 rec['passed']=dh<=10 and all(rec[m+'_relative_difference_percent']<=15 for m in ['HSV_value','Lab_Lstar'])
 checks.append(rec)
result={'revision':'R2.1','method':'Fixed 9x9 median RGB at corresponding physical surfaces; brightness checked with BOTH relative HSV V and CIELAB L* (sRGB/D65). Each <=15%; circular hue <=10 degrees. Coordinates declared before final lighting tuning.', 'sampling_note':'Added the wall above the left sconce beside the stag flag. The previous colour-only sample is the lower dado/rail and is retained in colour-verification.json; it is not the lit-wall brightness sample. Floor coordinates unchanged. R2 is the prior delivered capture.', 'checks':checks,'passed':all(c['passed'] for c in checks),'limits':'Two lit surface samples; no claim of full-image fidelity.'}
(doc/'brightness-verification.json').write_text(json.dumps(result,indent=2)+'\n')
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',22)
can=Image.new('RGB',(1800,1080),'#eee7df');dr=ImageDraw.Draw(can)
for i,im in enumerate(images):
 im=im.copy();mark=ImageDraw.Draw(im)
 for k,r in enumerate(spec):
  x,y=r['reference_pixel' if i==0 else 'runtime_pixel'];mark.rectangle((x-9,y-9,x+9,y+9),outline='#e82b59',width=3);mark.text((x+13,y-15),str(k+1),font=font,fill='#e82b59')
 im.thumbnail((600,600));can.paste(im,(i*600,55));dr.text((i*600+20,15),['Reference','R2 delivered','R2.1 Godot Mobile / Vulkan'][i],font=font,fill='#443b37')
for j,r in enumerate(spec):
 dr.text((20,675+j*195),r['name'],font=font,fill='#443b37')
 for i,(label,im) in enumerate(zip(['reference','R2','R2.1'],images)):
  x,y=r['reference_pixel' if i==0 else 'runtime_pixel'];crop=im.crop((x-28,y-28,x+28,y+28)).resize((112,112));can.paste(crop,(i*600+20,710+j*195))
  v=r[label];dr.text((i*600+145,728+j*195),f"V {v['HSV_value']:.3f} / L* {v['Lab_Lstar']:.2f}",font=font,fill='#443b37')
  if i==2:dr.text((i*600+145,765+j*195),f"Delta: {r['HSV_value_relative_difference_percent']:.1f}% V / {r['Lab_Lstar_relative_difference_percent']:.1f}% L*",font=font,fill='#443b37')
can.save(doc/'brightness-comparison.jpg',quality=94)
print(json.dumps(result,indent=2));assert result['passed']
