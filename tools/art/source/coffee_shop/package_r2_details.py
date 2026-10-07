"""Document actual camera anchors and optional native-pixel lettering crops."""
from pathlib import Path
import json,sys
from PIL import Image,ImageOps,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];slug=sys.argv[1];rev=sys.argv[2] if len(sys.argv)>2 else 'r2';doc=ROOT/'docs/design'/(slug+'-2026-10-07')
fit=json.loads((ROOT/'tools/art/source'/slug/'camera-r2.json').read_text());(doc/'camera-registration.json').write_text(json.dumps(fit,indent=2)+'\n')
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',22)
ref=ImageOps.pad(Image.open(doc/'reference.png').convert('RGB'),(1400,1400),color='#eee7df');run=Image.open(doc/'godot-whole.png').convert('RGB')
for im,key in [(ref,'observed_letterboxed_corners'),(run,'fitted_corners')]:
 dr=ImageDraw.Draw(im);pts=fit[key]
 for name,(x,y) in zip(['left','front','right'],pts):
  dr.ellipse((x-9,y-9,x+9,y+9),outline='#d52950',width=4);dr.text((x-55,y-35),name,font=font,fill='#d52950')
 back=[pts[0][j]+pts[2][j]-pts[1][j] for j in (0,1)];x,y=back
 dr.rectangle((x-8,y-8,x+8,y+8),outline='#365ce3',width=3);dr.text((x+10,y),'inferred back',font=font,fill='#365ce3')
can=Image.new('RGB',(2800,1455),'#eee7df');can.paste(ref,(0,55));can.paste(run,(1400,55));dr=ImageDraw.Draw(can)
dr.text((20,15),'Reference plinth edge intersections',font=font,fill='#443b37');dr.text((1420,15),'Rigid fit / residuals '+', '.join(f'{n:.1f}' for n in fit['residual_px'])+' px; no model scaling',font=font,fill='#443b37');can.save(doc/'camera-registration.png')
p=doc/'signage-crops.json'
if p.exists():
 boxes=json.loads(p.read_text());whole=Image.open(doc/'godot-whole.png').convert('RGB');w=max(480,max((r['box'][2]-r['box'][0])*3+50 for r in boxes));big_top=max(220,max(r['box'][3]-r['box'][1] for r in boxes)+95);h=max(600,max((r['box'][3]-r['box'][1])*3+big_top+60 for r in boxes))
 can=Image.new('RGB',(w*len(boxes),h),'#eee7df');dr=ImageDraw.Draw(can)
 for i,rec in enumerate(boxes):
  crop=whole.crop(rec['box']);can.paste(crop,(i*w+25,65));can.paste(crop.resize((crop.width*3,crop.height*3),Image.Resampling.NEAREST),(i*w+25,big_top));dr.text((i*w+12,15),rec['label'],font=font,fill='#443b37')
 dr.text((20,h-35),'Whole-view pixels above; 3x nearest-neighbour below (inspection only)',font=font,fill='#443b37');can.save(doc/'signage-check.png')
p=doc/'detail-views.json'
if p.exists():
 panels=json.loads(p.read_text());can=Image.new('RGB',(1600,850*((len(panels)+1)//2)),'#eee7df');dr=ImageDraw.Draw(can)
 for i,rec in enumerate(panels):
  im=ImageOps.contain(Image.open(ROOT/'output'/slug/rev/rec['file']).convert('RGB'),(800,800));x=i%2*800;y=i//2*850
  can.paste(im,(x+(800-im.width)//2,y+50+(800-im.height)//2));dr.text((x+20,y+15),rec['label'],font=font,fill='#443b37')
 can.save(doc/'asset-details.jpg',quality=94)
