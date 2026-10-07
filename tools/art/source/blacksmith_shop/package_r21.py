"""Inspect the three requested R2.1 changes in the actual registered Godot camera."""
from pathlib import Path
import io,subprocess,json
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];doc=ROOT/'docs/design/blacksmith_shop-2026-10-07';out=ROOT/'output/blacksmith_shop/r21'
a=Image.open(io.BytesIO(subprocess.check_output(['git','show','dffe008f:docs/design/blacksmith_shop-2026-10-07/godot-whole.png'],cwd=ROOT))).convert('RGB');b=Image.open(out/'godot-whole.png').convert('RGB')
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',23)
can=Image.new('RGB',(1600,1660),'#eee7df');d=ImageDraw.Draw(can)
for i,im in enumerate([a,b]):
 can.paste(im.resize((800,800)),(800*i,45));d.text((800*i+20,10),['R2 delivered','R2.1 Godot Mobile / Vulkan'][i],font=font,fill='#443b37')
for j,(label,box) in enumerate([('Smoke: fused volumes increase upward',(650,160,940,380)),('Cool unlit wall below left shelves',(155,790,285,970)),('Orange-red flame + ember bed',(620,640,785,778))]):
 for i,im in enumerate([a,b]):
  crop=im.crop(box);crop.thumbnail((650,210));crop=crop.resize((int(crop.width*min(650/crop.width,210/crop.height)),int(crop.height*min(650/crop.width,210/crop.height))));can.paste(crop,(i*800+30,905+j*250));d.text((i*800+20,860+j*250),label,font=font,fill='#443b37')
can.save(doc/'r21-changes.jpg',quality=95)
# Surface sample recorded independently of the warm lantern patch hue test.
import numpy as np
results=[]
for label,im in [('R2',a),('R2.1',b)]:
 ar=np.asarray(im);x,y=210,845;c=np.median(ar[y-4:y+5,x-4:x+5],axis=(0,1)).astype(int).tolist();results.append({'revision':label,'pixel':[x,y],'median_RGB':c})
(doc/'cold-wall-verification.json').write_text(json.dumps({'method':'Same unlit plaster surface and camera, 9x9 median RGB; demonstrates cold/dark correction separately from lit-surface hue test.','samples':results,'albedo_before':'766D65','albedo_after':'4E565F','review':'Visual acceptance pending art director.'},indent=2)+'\n')
