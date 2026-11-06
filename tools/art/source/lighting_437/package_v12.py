"""Unretouched same-camera triptych and matched screen-space brightness samples."""
from pathlib import Path
import hashlib,json,os,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/os.environ.get('LIGHTING_REVIEW_OUT','output/lighting-437-v12')
CAP=OUT/'captures';DOC=ROOT/'docs/design/lighting-437/v12';DOC.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
PRESETS=[('warm-noon','Warm noon'),('cool-morning','Cool morning'),('golden-dusk','Golden dusk')]
REGIONS={
 'grass_top':[(80,195),(100,177),(110,187),(90,207)],
 'grass_lower':[(22,422),(34,410),(63,424),(50,438)],
 'rock_shadow':[(187,225),(220,199),(238,219),(211,244)],
 'steps':[(86,240),(98,230),(106,236),(94,247)],
 'dock_boards':[(209,490),(227,480),(247,493),(230,510)]}
rows={};images={}
for name,_ in PRESETS:
 im=Image.open(CAP/(name+'-default-review.png')).convert('RGB');assert im.size==(360,800);images[name]=im
 a=np.asarray(im,dtype=float)/255;lum=a@np.array([.2126,.7152,.0722]);rows[name]={}
 for key,poly in REGIONS.items():
  mask=Image.new('1',im.size);ImageDraw.Draw(mask).polygon(poly,fill=1);q=np.array(mask)
  rows[name][key]={'pixels':int(q.sum()),'mean_Yprime':float(lum[q].mean()),'p10_Yprime':float(np.percentile(lum[q],10)),'mean_RGB_255':a[q].mean(0).tolist()}
  rows[name][key]['mean_RGB_255']=[v*255 for v in rows[name][key]['mean_RGB_255']]
  for kind in ['mean','p10']:
   rows[name][key][kind+'_percent_of_noon']=100*rows[name][key][kind+'_Yprime']/rows['warm-noon'][key][kind+'_Yprime']
 shutil.copy2(CAP/(name+'-default-review.png'),DOC/(name+'-default-review.png'))
assert min(rows['cool-morning'][r]['mean_percent_of_noon'] for r in ['grass_top','grass_lower'])>=80
assert 80<=np.mean([rows['golden-dusk'][r]['mean_percent_of_noon'] for r in ['grass_top','grass_lower']])<=90
assert rows['golden-dusk']['rock_shadow']['p10_percent_of_noon']>=60
metrics={'method':'Same fixed polygons in unretouched 360x800 Mobile captures. Mean and P10 Rec.709-weighted display RGB (Y prime = .2126 R + .7152 G + .0722 B), not linear physical luminance. No sea/sky/avatar pixels. Sampled patches do not establish a bound on every pixel in the scene.','polygons_xy':REGIONS,'samples':rows}
(DOC/'brightness-validation.json').write_text(json.dumps(metrics,indent=2)+'\n')
board=Image.new('RGB',(1080,956),'#f2f0e8');draw=ImageDraw.Draw(board)
for i,(name,title) in enumerate(PRESETS):
 x=i*360;board.paste(images[name],(x,52));draw.text((x+12,8),title,font=ImageFont.truetype(FONT,20),fill='#334646')
 draw.text((x+12,34),'360 x 800 | same camera | Mobile',font=ImageFont.truetype(FONT,11),fill='#334646')
 grass=np.mean([rows[name][r]['mean_percent_of_noon'] for r in ['grass_top','grass_lower']]);shadow=rows[name]['rock_shadow']['mean_percent_of_noon']
 draw.text((x+12,862),f'Grass {grass:.1f}% / shaded rock {shadow:.1f}%',font=ImageFont.truetype(FONT,14),fill='#334646')
 draw.text((x+12,886),'Matched patches; warm noon = 100%',font=ImageFont.truetype(FONT,12),fill='#334646')
 draw.text((x+12,912),'SGODOT-437 v1.2 | Liu Bei',font=ImageFont.truetype(FONT,13),fill='#334646')
 draw.text((x+12,934),'426 / 430 / 432 / 434 / 435 coast fixture',font=ImageFont.truetype(FONT,10),fill='#334646')
board.save(DOC/'lighting-three-presets.png')
control=images['warm-noon'].copy();draw=ImageDraw.Draw(control)
for i,(key,poly) in enumerate(REGIONS.items()):draw.line(poly+[poly[0]],fill='#e82d2d',width=2);draw.text(poly[0],str(i+1),fill='#e82d2d')
control.save(DOC/'brightness-regions.png')
report=json.loads((CAP/'render-validation.json').read_text())
if 'timing' in report:
 timings=report.pop('timing');summary={}
 for preset in ['original','warm_noon','cool_morning','golden_dusk']:
  blocks=[b for b in timings if b['preset']==preset];summary[preset]={}
  for key in ['cpu_ms','gpu_ms']:
   values=np.array([v for b in blocks for v in b[key]])
   summary[preset][key]={'samples':len(values),'median':float(np.median(values)),'p95':float(np.percentile(values,95)),'block_medians':[float(np.median(b[key])) for b in blocks]}
 (DOC/'timing-validation.json').write_text(json.dumps({'renderer':report['renderer'],'presets':summary,'method':'3 interleaved cycles; 45 warmup + 90 measured frames per block, middle order reversed; fixed camera, geometry, sea/foam time.','scope':'Deck Vulkan Mobile viewport CPU/GPU; not physical phone or whole-app timing.'},indent=2)+'\n')
 print('timing',json.dumps(summary))
(DOC/'render-validation.json').write_text(json.dumps(report,indent=2)+'\n')
if (OUT/'android/smoke.json').exists():
 shutil.copy2(OUT/'android/smoke.json',DOC/'android-validation.json');(DOC/'android').mkdir(exist_ok=True)
 for name in ['warm_noon','cool_morning','golden_dusk']:shutil.copy2(OUT/('android/'+name+'-viewport.png'),DOC/('android/'+name+'.png'))
(DOC/'media-manifest.json').write_text(json.dumps({str(p.relative_to(DOC)):{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(DOC.rglob('*.png'))},indent=2)+'\n')
print(json.dumps({name:{region:round(v['mean_percent_of_noon'],1) for region,v in samples.items()} for name,samples in rows.items()},indent=2))
