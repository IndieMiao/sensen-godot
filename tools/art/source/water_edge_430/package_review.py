from pathlib import Path
import json,shutil,hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageFont
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/water-edge-430-v11';CAP=OUT/'captures';DOC=ROOT/'docs/design/water-edge-430';DOC.mkdir(parents=True,exist_ok=True)
font='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
def label(im,title,subtitle,small=False):
 im=im.convert('RGB');d=ImageDraw.Draw(im);w,h=im.size;fs=14 if small else 21
 d.rectangle((0,0,w,58 if small else 70),fill='#f2f0e8');d.text((12,8),title,font=ImageFont.truetype(font,fs),fill='#334646');d.text((12,30 if small else 39),subtitle,font=ImageFont.truetype(font,11 if small else 15),fill='#334646')
 return im
files=[]
for name,title,subtitle in [('default-review','SGODOT-430 / Water edge v1.1','360 x 800 | 0.7 contact alpha / 5.5 s tide'),('coast-overview','12 m modular shore / five foam components','Coast #831 d72d74f4 | QA-only 0.25 m opaque wet band'),('close-review','Continuous contact / irregular moving edge','1 texture read / 1 pass | 0.10 m push and retreat'),('steps-review','2 m water-access stair outlet','Contact fades removed at the adjoining shore'),('pile-review','Timber pile / same 0.10 m tide','Contact remains solid; no whole-ring opacity pulsing')]:
 im=label(Image.open(CAP/(name+'.png')),title,subtitle,name=='default-review')
 if name=='default-review':
  d=ImageDraw.Draw(im);d.rectangle((0,746,360,800),fill='#f2f0e8');d.text((12,753),'Expanded edge ~0.30-0.34 m / 0.10 m motion',font=ImageFont.truetype(font,11),fill='#334646');d.text((12,775),'Liu Bei | reference water Y=0.20 m',font=ImageFont.truetype(font,11),fill='#334646')
 im.save(DOC/(name+'.png'));files.append(name+'.png')
frames=[label(Image.open(p),'Water edge v1.1 / 5.5 s tide','Outer edge moves 0.10 m | contact stays solid',True) for p in sorted((CAP/'motion').glob('*.png'))]
assert len(frames)==110
palette=Image.new('RGB',(360*4,800))
for i,n in enumerate([0,27,55,82]):palette.paste(frames[n],(i*360,0))
palette=palette.quantize(colors=256)
encoded=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
encoded[0].save(DOC/'motion-review.gif',save_all=True,append_images=encoded[1:],duration=50,loop=0,optimize=False,disposal=1)
frames[0].save(DOC/'motion-review.apng',format='PNG',save_all=True,append_images=frames[1:],duration=50,loop=0,disposal=0,blend=0)
files+=['motion-review.gif','motion-review.apng']
a=np.asarray(Image.open(CAP/'motion/000.png')).astype(float);b=np.asarray(Image.open(CAP/'loop-end.png')).astype(float)
loop=float(abs(a-b).max());assert loop==0,loop
before=Image.open(ROOT/'output/water-edge-430/captures/default-review.png');after=Image.open(CAP/'default-review.png')
comparison=Image.new('RGB',(720,800));comparison.paste(label(before,'v1 / 13f4dcaab','Original weak broken edge',True),(0,0));comparison.paste(label(after,'v1.1 / revised shader','Continuous white contact / moving outer edge',True),(360,0));comparison.save(DOC/'default-comparison.png');files.append('default-comparison.png')
metrics=json.loads((OUT/'edge-motion-validation.json').read_text());shutil.copy2(OUT/'edge-motion-validation.json',DOC/'edge-motion-validation.json')
shutil.copy2(CAP/'render-validation.json',DOC/'render-validation.json')
report={'passed':True,'revision':'v1.1','loop_end_max_rgb_255':loop,'frame_interval_s':.05,'gif_duration_ms':5500,'gif_frames':110,'motion_clock':'110 actual Mobile-rendered shader samples at t=i/20 s; TIME replaced by uniform in QA only; not device FPS recording','edge_measurement':'edge-motion-validation.json'}
(OUT/'motion-validation.json').write_text(json.dumps(report,indent=2)+'\n');shutil.copy2(OUT/'motion-validation.json',DOC/'motion-validation.json')
manifest={name:{'bytes':(DOC/name).stat().st_size,'sha256':hashlib.sha256((DOC/name).read_bytes()).hexdigest()} for name in files}
(DOC/'media-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest,indent=2))
