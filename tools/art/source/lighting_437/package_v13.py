"""Package unretouched v1.3 captures, fixed colour samples and shadow evidence."""
from pathlib import Path
import hashlib,json,colorsys,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'output/lighting-437-v13';CAP=OUT/'captures';DOC=ROOT/'docs/design/lighting-437/v13';DOC.mkdir(parents=True,exist_ok=True)
OLD=ROOT/'docs/design/lighting-437/v12';FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
old_regions=json.loads((OLD/'brightness-validation.json').read_text())['polygons_xy']
REGIONS={'grass_top':old_regions['grass_top'],'grass_lower':old_regions['grass_lower'],'rock_lit':old_regions['rock_shadow'],'rock_shade':[(93,317),(99,321),(97,325),(91,322)],'dock_top':old_regions['dock_boards'],'steps':old_regions['steps']}
NAMES=[('warm-noon','Warm noon'),('cool-morning','Cool morning'),('golden-dusk','Golden dusk')]
images={};samples={};old_samples={};background={}
def measure(im):
 a=np.array(im,dtype=float)/255;row={}
 for key,poly in REGIONS.items():
  mask=Image.new('1',im.size);ImageDraw.Draw(mask).polygon(poly,fill=1);m=np.array(mask);v=a[m].mean(0)
  row[key]={'pixels':int(m.sum()),'mean_rgb_255':(v*255).tolist(),'hex':'#'+''.join(f'{round(x*255):02X}' for x in v),'mean_Yprime':float(v@np.array([.2126,.7152,.0722])),'hsl_saturation':colorsys.rgb_to_hls(*v)[2]}
 return row
for name,title in NAMES:
 im=Image.open(CAP/(name+'-default-review.png')).convert('RGB');assert im.size==(360,800);images[name]=im;samples[name]=measure(im)
 old=Image.open(OLD/(name+'-default-review.png')).convert('RGB');old_samples[name]=measure(old)
 d=np.abs(np.array(im,dtype=float)-np.array(old,dtype=float));background[name]={'sky_far_max_255':float(d[:132].max()),'near_sea_max_255':float(d[640:].max())}
 assert max(background[name].values())==0
 shutil.copy2(CAP/(name+'-default-review.png'),DOC/(name+'-default-review.png'))
for name in samples:
 for key,v in samples[name].items():
  v['brightness_percent_of_noon']=100*v['mean_Yprime']/samples['warm-noon'][key]['mean_Yprime']
  v['hsl_saturation_percent_of_noon']=100*v['hsl_saturation']/samples['warm-noon'][key]['hsl_saturation']
assert samples['golden-dusk']['rock_lit']['mean_rgb_255'][0]>samples['golden-dusk']['rock_lit']['mean_rgb_255'][2]
assert 72<=samples['golden-dusk']['rock_shade']['brightness_percent_of_noon']<=76
assert all(68<=samples['cool-morning'][k]['hsl_saturation_percent_of_noon']<=76 for k in ['grass_top','grass_lower'])
metrics={'method':'Mean display RGB in fixed, outlined polygons of unretouched 360x800 Mobile captures. Y-prime = .2126 R + .7152 G + .0722 B. HSL saturation, not HSV. Values are local patch measurements, not bounds over the full scene.','polygons_xy':REGIONS,'targets':{'rock_lit':'#8E7C6E','rock_shade':'#5F5A6E','dock_top':'#94693F'},'samples':samples,'v12_same_region_samples':old_samples,'unchanged_background_pixels':background}
(DOC/'color-validation.json').write_text(json.dumps(metrics,indent=2)+'\n')
board=Image.new('RGB',(1080,996),'#f2f0e8');draw=ImageDraw.Draw(board)
for i,(name,title) in enumerate(NAMES):
 x=360*i;board.paste(images[name],(x,52));draw.text((x+12,8),title,font=ImageFont.truetype(FONT,20),fill='#334646');draw.text((x+12,34),'360 x 800 | same camera | Mobile',font=ImageFont.truetype(FONT,11),fill='#334646')
 row=samples[name];lines=[f"Lit rock {row['rock_lit']['hex']}",f"Shade {row['rock_shade']['hex']} / {row['rock_shade']['brightness_percent_of_noon']:.1f}% noon",f"Dock top {row['dock_top']['hex']}"]
 if name=='cool-morning':lines=[f"Grass {row['grass_top']['hex']} / {row['grass_lower']['hex']}",f"HSL-S {row['grass_top']['hsl_saturation_percent_of_noon']:.1f}% / {row['grass_lower']['hsl_saturation_percent_of_noon']:.1f}% noon",'Morning angle unchanged']
 if name=='golden-dusk':lines.append('Sun (-18, -13, 0); upper-right shadows')
 for j,line in enumerate(lines):draw.text((x+12,861+j*23),line,font=ImageFont.truetype(FONT,13),fill='#334646')
 draw.text((x+12,970),'SGODOT-437 v1.3 | Liu Bei',font=ImageFont.truetype(FONT,13),fill='#334646')
board.save(DOC/'lighting-three-presets.png')
control=Image.new('RGB',(720,880),'#f2f0e8');draw=ImageDraw.Draw(control)
for i,name in enumerate(['warm-noon','golden-dusk']):
 control.paste(images[name],(i*360,30));draw.text((i*360+10,8),name,fill='#334646')
 for j,(key,poly) in enumerate(REGIONS.items()):
  pts=[(x+i*360,y+30) for x,y in poly];draw.line(pts+[pts[0]],fill='#ed3434',width=1);draw.text(pts[0],str(j+1),fill='#ed3434')
draw.text((10,842),'1 grass top; 2 grass lower; 3 lit rock; 4 shaded inner facet;',fill='#334646');draw.text((10,860),'5 dock board tops (includes grain/seams); 6 steps. Same polygons in JSON.',fill='#334646')
control.save(DOC/'color-regions.png')
for name in ['golden-dusk-shadow-probe','golden-dusk-shadow-probe-off']:shutil.copy2(CAP/(name+'.png'),DOC/(name+'.png'))
report=json.loads((CAP/'render-validation.json').read_text());timings=report.pop('timing',[]);summary={}
for preset in ['original','warm_noon','cool_morning','golden_dusk']:
 blocks=[b for b in timings if b['preset']==preset];summary[preset]={}
 for key in ['cpu_ms','gpu_ms']:
  values=np.array([v for b in blocks for v in b[key]])
  summary[preset][key]={'samples':len(values),'median':float(np.median(values)),'p95':float(np.percentile(values,95))}
(DOC/'timing-validation.json').write_text(json.dumps({'renderer':report['renderer'],'presets':summary,'scope':'Deck Vulkan Mobile viewport; 3 interleaved cycles, 270 samples per preset. Not a physical-phone or whole-app measurement.'},indent=2)+'\n')
(DOC/'render-validation.json').write_text(json.dumps(report,indent=2)+'\n')
for name in ['cold-validation.json','resource-validation.json']:shutil.copy2(OUT/name,DOC/name)
(DOC/'media-manifest.json').write_text(json.dumps({p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(DOC.glob('*.png'))},indent=2)+'\n')
print(json.dumps({'colours':{k:samples['golden-dusk'][k] for k in ['rock_lit','rock_shade','dock_top']},'timings':summary,'background':background},indent=2))
