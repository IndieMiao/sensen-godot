"""Measure actual rendered output sRGB pixel brightness; retain all sample masks."""
from pathlib import Path
import json, shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import binary_erosion

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
CAP=ROOT/'output/ground-detail-428/captures';DOC=ROOT/'docs/design/ground-detail-428'
COLORS={'deep':(255,0,0),'ordinary':(0,255,0),'sunlit':(0,0,255),'sand':(255,255,0),'wet_sand':(0,255,255)}
COEFF=np.array([.2126,.7152,.0722])
def read(name):return np.asarray(Image.open(CAP/name).convert('RGB'))
def y(a):return a@COEFF/255
def font(size):return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',size)
def main():
 DOC.mkdir(parents=True,exist_ok=True);records=[]
 for view in ['default','whole','grass_close','sand_close']:
  rgb=read(view+'.png');classes=read(view+'-classes.png');light=y(read(view+'-lighting.png'))
  masks={k:binary_erosion(np.max(abs(classes.astype(int)-c),axis=2)<3,iterations=1) for k,c in COLORS.items()}
  valid=np.logical_or.reduce(list(masks.values()));reference=float(np.median(light[valid]))
  masks={k:m & (abs(light-reference)<.008) for k,m in masks.items()}
  samples={k:{'pixels':int(m.sum()),'mean_output_srgb_brightness':float(y(rgb)[m].mean())} for k,m in masks.items() if m.any()}
  contrasts={}
  for label,a,b in [('grass','ordinary','deep'),('sand_wet_sand','sand','wet_sand')]:
   if a in samples and b in samples:
    contrasts[label]=100*(1-samples[b]['mean_output_srgb_brightness']/samples[a]['mean_output_srgb_brightness'])
  if 'grass' in contrasts:assert contrasts['grass']>=15,(view,contrasts)
  if 'sand_wet_sand' in contrasts:assert contrasts['sand_wet_sand']>=15,(view,contrasts)
  mask=np.zeros_like(rgb);outline=rgb.copy()
  for k,m in masks.items():
   mask[m]=COLORS[k];outline[m & ~binary_erosion(m)]=COLORS[k]
  Image.fromarray(mask).save(DOC/(view+'-sample-mask.png'))
  Image.fromarray(outline).save(DOC/(view+'-sampling.png'))
  shutil.copy2(CAP/(view+'.png'),DOC/(view+'.png'))
  lines=[]
  for label,val in contrasts.items():
   a,b=('ordinary','deep') if label=='grass' else ('sand','wet_sand')
   lines.append(f'{"Grass deep / ordinary" if label=="grass" else "Wet / dry sand"}: {val:.2f}% darker')
   lines.append(f"Mean Y': {samples[b]['mean_output_srgb_brightness']:.4f} / {samples[a]['mean_output_srgb_brightness']:.4f}")
  lines+=['Same warm light as #827; output sRGB weighted pixel means.', 'Masks: red=deep, green=ordinary, blue=sun; yellow=dry, cyan=wet.']
  if view=='default':
   w,h=rgb.shape[1],rgb.shape[0];sheet=Image.new('RGB',(w*2+36,h+230),'#edf0ed');d=ImageDraw.Draw(sheet)
   d.text((12,12),'SGODOT-428 | default 360 x 800 | 6.72 m / 43 deg',font=font(20),fill='#202c28')
   d.text((12,42),'Grass / paving / wood / dry sand / wet sand, top to bottom',font=font(18),fill='#425348')
   sheet.paste(Image.fromarray(rgb),(12,76));sheet.paste(Image.fromarray(outline),(w+24,76))
   for i,line in enumerate(lines):d.text((12,h+88+i*22),line,font=font(17),fill='#202c28')
   sheet.save(DOC/'default-review.png')
  else:
   im=Image.fromarray(rgb);sheet=Image.new('RGB',(im.width,im.height+155),'#edf0ed');sheet.paste(im,(0,0));d=ImageDraw.Draw(sheet)
   title={'whole':'Whole 20 x 20 m test terrain | wide view, 28 m camera', 'grass_close':'Grass closeup | 8 m camera', 'sand_close':'Dry sand / wet sand / tide line | 6 m camera'}[view]
   d.text((14,im.height+8),title,font=font(20),fill='#202c28')
   for i,line in enumerate(lines):d.text((14,im.height+36+i*19),line,font=font(16),fill='#202c28')
   sheet.save(DOC/(view+'-review.png'))
  records.append({'view':view,'samples':samples,'contrast_percent':contrasts,'lighting_reference_Yprime':reference})
 shutil.copy2(CAP/'hard_close.png',DOC/'hard_close.png')
 report={'passed':True,'metric':"Y'=(0.2126 R+0.7152 G+0.0722 B)/255 from rendered sRGB; 100*(reference-dark)/reference",'sampling':'diagnostic class interiors eroded 1px, equal-albedo warm-light control within +/-0.008 of median; entire remaining masks, no hand-picked darkest pixel','views':records}
 (DOC/'brightness-validation.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({r['view']:r['contrast_percent'] for r in records},indent=2))
if __name__=='__main__':main()
