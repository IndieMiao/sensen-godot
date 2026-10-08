from pathlib import Path
import json,hashlib,subprocess,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont
r=Path(__file__).resolve().parents[4];o=r/'output/blacksmith_shop/r25';d=r/'docs/design/blacksmith_shop-smoke-r25-2026-10-08';d.mkdir(exist_ok=True)
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',23)
for n in ['godot-whole.png','smoke-detail.png','godot-verification.json','particle-clips.json']:shutil.copy2(o/n,d/n)
canvas=Image.new('RGB',(1800,660),'#eef0ed');draw=ImageDraw.Draw(canvas);samples=[]
for i,t in enumerate([.25,4,7.5]):
 p=o/f'smoke-sample-{i}.jpg'
 subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(t),'-i',str(o/'smoke-motion.mp4'),'-frames:v','1',str(p)],check=True)
 im=Image.open(p).convert('RGB');samples.append(np.array(im).astype(float));canvas.paste(im.resize((600,600)),(600*i,60));draw.text((600*i+12,14),f'R2.5 smoke / {t}s real-time',font=font,fill='#393e43')
canvas.save(d/'smoke-timeline.jpg',quality=94)
assert all(a.mean()>5 for a in samples)
probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_name,width,height,nb_frames','-of','json',str(o/'smoke-motion.mp4')]))
media={'clip':'smoke-motion.mp4','sha256':hashlib.sha256((o/'smoke-motion.mp4').read_bytes()).hexdigest(),'ffprobe':probe,'accelerated':False,'sample_times':[.25,4,7.5],'sampled_black_frames':0,'pixel_motion':[float(abs(a-b).mean()) for a,b in zip(samples,samples[1:])]};assert min(media['pixel_motion'])>.05
(d/'media-verification.json').write_text(json.dumps(media,indent=2)+'\n')
for output,items in [('comparison.png',[(r/'docs/design/blacksmith_shop-2026-10-07/reference.png','Figma 545:2965'),(o/'godot-whole.png','R2.5 / Mobile Vulkan / smoke texture only')]),('smoke-before-after.jpg',[(r/'docs/design/blacksmith_shop-smoke-r24-2026-10-08/smoke-detail.png','R2.4 / pale soft plume'),(o/'smoke-detail.png','R2.5 / shaded lobes, narrow feather')])]:
 c=Image.new('RGB',(1800,940),'#eef0ed');draw=ImageDraw.Draw(c)
 for i,(p,label) in enumerate(items):
  im=Image.open(p).convert('RGB');im.thumbnail((900,900));c.paste(im,(900*i+(900-im.width)//2,40));draw.text((900*i+12,8),label,font=font,fill='#393e43')
 c.save(d/output)
# Compare all runtime FX/room/scene bytes with both the starting snapshot and git.
b=json.loads((o/'before-hashes.json').read_text());protected={n:h for n,h in b.items() if n!='assets/rooms/_shared/fx/smoke_strip.png'}
after={n:hashlib.sha256((r/n).read_bytes()).hexdigest() for n in protected};assert after==protected
for n,h in protected.items():assert hashlib.sha256(subprocess.check_output(['git','show','dfe6cbe0:'+n])).hexdigest()==h,n
record={'baseline_commit':'dfe6cbe0','changed_runtime_files':['assets/rooms/_shared/fx/smoke_strip.png'],'protected_count':len(protected),'before':protected,'after':after,'all_byte_identical':True,'workbench':'工作台未改动','fire_helper_smoke_parameters_layout_and_room_unchanged':True}
(d/'preservation.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
# Explicit review-image patches, not a whole-image fidelity score.
im=Image.open(o/'smoke-detail.png').convert('RGB');a=np.array(im).astype(float);bg=np.median(a[40:100,40:100],axis=(0,1));weights=np.array([.2126,.7152,.0722])
def linear(rgb):
 x=rgb/255;return np.where(x<=.04045,x/12.92,((x+.055)/1.055)**2.4)
patches=[];annotated=im.copy();draw=ImageDraw.Draw(annotated)
for name,x,y in [('Upper shadow',980,425),('Middle shadow',880,760),('Lower shadow',490,939)]:
 rgb=np.median(a[y-10:y+10,x-10:x+10],axis=(0,1));encoded=1-rgb@weights/(bg@weights);physical=1-linear(rgb)@weights/(linear(bg)@weights)
 assert encoded>=.15
 patches.append({'name':name,'box_xyxy':[x-10,y-10,x+10,y+10],'median_rgb':rgb.tolist(),'srgb_luma_deficit':float(encoded),'linear_luminance_deficit':float(physical)})
 draw.rectangle((x-10,y-10,x+10,y+10),outline='#2555a0',width=3);draw.text((x-230,y-40),f'{name}: {encoded:.1%} darker',font=font,fill='#2555a0')
draw.rectangle((40,40,100,100),outline='#2555a0',width=3);draw.text((110,50),f'Unchanged background: {bg.astype(int).tolist()}',font=font,fill='#2555a0')
annotated.save(d/'contrast-sampling.png')
tex=np.array(Image.open(r/'assets/rooms/_shared/fx/smoke_strip.png'));edge=[]
for i in range(4):
 alpha=tex[:,i*256:(i+1)*256,3]/255
 outer=np.sqrt(np.sum(alpha>=.1)/np.pi);inner=np.sqrt(np.sum(alpha>=.9)/np.pi);radius=np.sqrt(np.sum(alpha>=.5)/np.pi)
 ratio=(outer-inner)/radius;assert ratio<.1
 edge.append({'frame':i,'equivalent_radius_px':float(radius),'alpha10_90_equivalent_feather_px':float(outer-inner),'fraction_of_radius':float(ratio),'method':'Equivalent-area radii at alpha 10/90%; average silhouette feather, not a maximum per-edge bound.'})
thumb=Image.open(o/'godot-whole.png').convert('RGB').resize((350,350),Image.Resampling.LANCZOS);thumb.save(d/'whole-thumbnail.png')
(d/'contrast-verification.json').write_text(json.dumps({'background_median_rgb':bg.tolist(),'patches':patches,'alpha_feather':edge,'rendered_sample_scope':'Three marked fully visible shadow patches in the actual unchanged review camera/background. Late fading puffs are naturally lighter.','thumbnail_px':[350,350],'texture_authoring_shadow_rgb':[150,154,163],'texture_authoring_highlight_rgb':[229,225,215],'tone_mapping':'Existing ACES; input RGB compensates its lift. No material or lighting edits.'},indent=2)+'\n')
shutil.copy2(o/'standalone-validation.json',d/'standalone-validation.json')
print('PACKAGED',len(protected),'protected files',patches,edge)
