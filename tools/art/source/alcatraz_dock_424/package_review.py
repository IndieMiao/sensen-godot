from pathlib import Path
import json,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/alcatraz-dock-424';CAP=OUT/'captures';DOC=ROOT/'docs/design/alcatraz-dock-424'
def f(n):return ImageFont.truetype('/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',n)
r=json.loads((CAP/'render-validation.json').read_text());assert r['passed'];m=json.loads((ROOT/'assets/landmarks/alcatraz_island/alc_dock_manifest.json').read_text())
# Detect only orange bridge geometry; new foreground props must not cover it.
a=np.array(Image.open(CAP/'03_opening_before.png').convert('RGB'));b=np.array(Image.open(CAP/'04_dock_opening.png').convert('RGB'))
roi=a[55:135,:140].astype(float);mask=(roi[:,:,0]>roi[:,:,1]*1.16)&(roi[:,:,1]>roi[:,:,2]*1.08)&(roi[:,:,0]>100)
assert mask.sum()>80;assert np.array_equal(a[55:135,:140][mask],b[55:135,:140][mask])
r['bridge_pixel_check']={'passed':True,'region_xywh':[0,55,140,80],'orange_bridge_pixels':int(mask.sum()),'changed_pixels':0,'method':'before/after fixed opening, orange bridge geometry pixels, original PNG bytes'}
(DOC/'render-validation.json').write_text(json.dumps(r,indent=2)+'\n')
canvas=Image.new('RGB',(1500,850),'#f4f1e8');canvas.paste(Image.open(CAP/'01_scale_lineup.png'),(0,68));d=ImageDraw.Draw(canvas)
d.text((20,12),'刘备 · 恶魔岛码头小件 · 5 件 / 各 1 surface / 哑光顶点色',font=f(29),fill='#35432f')
labels={'alc_dock_bollard':'系缆桩','alc_dock_crates':'木箱与绳卷','alc_dock_shelter':'双长椅遮棚','alc_dock_welcome':'空白欢迎牌','alc_dock_planter':'大型花箱 ×2'}
for row in r['lineup_labels']:
 name=row['asset'];x=row['screen_x'];spec=m['assets'][name]
 for yy,text in [(760,labels[name]),(789,name.removeprefix('alc_dock_')+' · '+str(spec['triangles'])+' tri'),(816,' × '.join(f'{v:.2f}' for v in spec['dimensions_m'])+' m')]:
  d.text((x,yy),text,font=f(19 if yy==760 else 16),fill='#35432f',anchor='mt')
d.text((1330,760),'人物 1.75 m',font=f(20),fill='#35432f',anchor='mt');canvas.save(DOC/'scale-lineup.png')
for src,dest in [('04_dock_opening.png','dock-opening.png'),('05_dock_context.png','dock-context.png'),('06_dock_top.png','dock-top.png'),('02_dock_detail.png','dock-detail.png')]:shutil.copy2(CAP/src,DOC/dest)
canvas=Image.new('RGB',(756,946),'#f4f1e8');d=ImageDraw.Draw(canvas)
d.text((14,9),'刘备 · 码头开场 / 默认 43°、6.72 m、360×800',font=f(23),fill='#35432f')
for i,(src,label) in enumerate([('03_opening_before.png','b16c3198 + #801 审阅背景'),('04_dock_opening.png','本次码头 7 个建议实例')]):
 d.text((12+i*372,45),label,font=f(18),fill='#35432f');canvas.paste(Image.open(CAP/src),(12+i*372,76))
d.text((14,887),'左上大桥像素保持一致；高件避让缩放键及右下预留区，欢迎牌避让 Map。',font=f(17),fill='#35432f')
d.text((14,916),'主体、导航、镜头和海面保留；岸石沿用 #801，仅作审阅背景。',font=f(17),fill='#35432f');canvas.save(DOC/'opening-comparison.png')
# Annotated evidence is separate from the untouched native opening image.
img=Image.open(CAP/'04_dock_opening.png').convert('RGB').resize((720,1600),Image.Resampling.NEAREST);d=ImageDraw.Draw(img)
for x,y,w,h in [(98.76958,497.0955,48,64),(300,352,44,44),(300,400,44,44)]:d.rectangle(((x-12)*2,(y-12)*2,(x+w+12)*2,(y+h+12)*2),outline='#28ffbf',width=2)
img.save(DOC/'hud-clearance.png')
print('PACKAGED',int(mask.sum()),'unchanged bridge pixels')
