from pathlib import Path
import json,shutil,hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageFont
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/water-edge-430';CAP=OUT/'captures';DOC=ROOT/'docs/design/water-edge-430';DOC.mkdir(parents=True,exist_ok=True)
font='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
def label(im,title,subtitle,small=False):
 im=im.convert('RGB');d=ImageDraw.Draw(im);w,h=im.size;fs=14 if small else 21
 d.rectangle((0,0,w,58 if small else 70),fill='#f2f0e8');d.text((12,8),title,font=ImageFont.truetype(font,fs),fill='#334646');d.text((12,30 if small else 39),subtitle,font=ImageFont.truetype(font,11 if small else 15),fill='#334646')
 return im
files=[]
for name,title,subtitle in [('default-review','SGODOT-430 / Water edge kit','360 x 800 | default 6.72 m / pitch 43 deg'),('coast-overview','12 m modular shore / five foam components','Coast #831 d72d74f4 | QA-only 0.25 m opaque wet band'),('close-review','Outer + inner corner / continuous single layer','1 texture read / 1 pass | wet band belongs to opaque shore'),('steps-review','2 m water-access stair outlet','Water Y = 0.20 m | contact at last submerged tread')]:
 im=Image.open(CAP/(name+'.png'));im=label(im,title,subtitle,name=='default-review')
 if name=='default-review':
  d=ImageDraw.Draw(im);d.rectangle((0,746,360,800),fill='#f2f0e8');d.text((12,753),'Coast #831 + QA wet band 0.25 m',font=ImageFont.truetype(font,12),fill='#334646');d.text((12,775),'Liu Bei | review only | no game integration',font=ImageFont.truetype(font,11),fill='#334646')
 im.save(DOC/(name+'.png'));files.append(name+'.png')
frames=[]
for p in sorted((CAP/'motion').glob('*.png')):
 im=label(Image.open(p),'Water edge / 4 s gentle loop','Mobile renderer | 0.25 Hz / 6% opacity variation')
 frames.append(im)
# Shared palette and no dithering: moving dither must not masquerade as foam motion.
palette=frames[0].quantize(colors=192)
encoded=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
# GIF granularity is 10ms: 70/60/70 ms totals exactly 4 seconds for 60 frames.
encoded[0].save(DOC/'motion-review.gif',save_all=True,append_images=encoded[1:],duration=[70,60,70]*20,loop=0,optimize=False,disposal=1)
files.append('motion-review.gif')
frames[0].save(DOC/'motion-review.apng',format='PNG',save_all=True,append_images=frames[1:],duration=[70,60,70]*20,loop=0,disposal=0,blend=0)
files.append('motion-review.apng')
a=np.asarray(Image.open(CAP/'motion/000.png')).astype(float);b=np.asarray(Image.open(CAP/'loop-end.png')).astype(float)
loop=float(abs(a-b).max());assert loop==0,loop
changes=[]
for p,q in zip(sorted((CAP/'motion').glob('*.png')),sorted((CAP/'motion').glob('*.png'))[1:]):
 delta=abs(np.asarray(Image.open(p)).astype(float)-np.asarray(Image.open(q)).astype(float));changes.append({'max_rgb_255':float(delta.max()),'mean_rgb_255':float(delta.mean())})
assert max(c['max_rgb_255'] for c in changes)<12
before=np.asarray(Image.open(CAP/'default-control-no-foam.png')).astype(float);after=np.asarray(Image.open(CAP/'default-review.png')).astype(float);delta=abs(before-after)
report={'passed':True,'loop_end_max_rgb_255':loop,'frame_interval_s':1/15,'largest_adjacent_frame_rgb_255':max(c['max_rgb_255'] for c in changes),'max_frame_mean_rgb_255':max(c['mean_rgb_255'] for c in changes),'opening_changed_pixels':int((delta.max(2)>1).sum()),'gif_duration_ms':4000,'gif_frames':60,'motion_clock':'60 rendered shader samples at t=i/15 s; TIME replaced by uniform only in QA; not device FPS recording','no_flash_check':'max adjacent raw RGB delta <12/255; seam t=0 and t=4 identical'}
(OUT/'motion-validation.json').write_text(json.dumps(report,indent=2)+'\n')
for src in [OUT/'geometry-validation.json',OUT/'import-validation.json',CAP/'render-validation.json',OUT/'motion-validation.json']:
 shutil.copy2(src,DOC/src.name)
manifest={name:{'bytes':(DOC/name).stat().st_size,'sha256':hashlib.sha256((DOC/name).read_bytes()).hexdigest()} for name in files}
(DOC/'media-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(report,indent=2));print(manifest)
