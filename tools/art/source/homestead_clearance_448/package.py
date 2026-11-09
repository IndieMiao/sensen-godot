"""Compose review sheets from the captured Godot pixels; never redraw the scene."""
from pathlib import Path
import json,shutil,sys
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];Q=ROOT/'output/homestead-448';OUT=ROOT/'docs/design/homestead-clearance-448';OUT.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def f(n):return ImageFont.truetype(FONT,n)
def sheet(name,title,items,note,crop=None):
 w=360;h=800 if crop is None else round((crop[3]-crop[1])*w/(crop[2]-crop[0]));out=Image.new('RGB',(20+len(items)*370,135+h),'#f4f0e8');d=ImageDraw.Draw(out);d.text((15,10),title,font=f(24),fill='#302c28')
 for i,(label,file) in enumerate(items):
  image=Image.open(Q/'captures'/(file+'.png')).convert('RGB')
  if crop:image=image.crop(crop).resize((w,h),Image.Resampling.NEAREST)
  x=15+i*370;d.text((x,51),label,font=f(19),fill='#302c28');out.paste(image,(x,80))
 d.text((15,87+h),note,font=f(16),fill='#50483d');assert max(out.size)<=1600;out.save(OUT/(name+'.png'),optimize=True)
sheet('SGODOT-448_lv4-lv5_default','SGODOT-448 · Lv4 / Lv5 门罩 · 默认农场镜头',[
 ('Lv4 原屋','before_lv4_a_default'),('Lv5 a 修前','before_lv5_a_default'),('Lv5 a 修后','after_lv5_a_default'),('Lv5 b 修后','after_lv5_b_default')], '360×800 原图；各等级原生开场，修前后机位一致；14.5° / 俯43°。赵云')
sheet('SGODOT-448_hood_detail','SGODOT-448 · 门罩贴墙收回 / 深一档瓦色',[(f'{look} · {label}',f'{phase}_lv5_{look}_close') for look in ['a','b'] for phase,label in [('before','修前'),('after','修后')]],'近景实渲局部等比放大；新门罩全部收在屋格内，背边离主檐10.5–11.9cm。赵云',(105,280,315,470))
for lv in [8,15]:
 sheet(f'SGODOT-448_lv{lv}_default',f'SGODOT-448 · Lv{lv} 左翼退让 · 默认农场镜头',[(f'{look} · {label}',f'{phase}_lv{lv}_{look}_default') for look in ['a','b'] for phase,label in [('before','修前'),('after','修后')]],'360×800原图；长凳、房屋锚点、原生机位及导航均不移动。赵云')
 sheet(f'SGODOT-448_lv{lv}_bench',f'SGODOT-448 · Lv{lv} 原长凳坐姿 / 墙体间隙',[(f'{look} · {label}',f'{phase}_lv{lv}_{look}_bench_seated') for look in ['a','b'] for phase,label in [('before','修前'),('after','修后')]],'近景局部等比放大；复用sit_idle做隔离穿模检查，不代表农场Rest坐姿已接入。赵云',(0,180,255,465))
sheet('SGODOT-448_door_approach','SGODOT-448 · 原导航的实际入门接近点',[('Lv5 a', 'after_lv5_a_door_approach'),('Lv5 b','after_lv5_b_door_approach')],'只暂缓室内跳转拍照；主屋、人物和导航不变。赵云')
# Actual projected triangles, not the modelling helper's footprint.
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
out=Image.new('RGB',(1460,940),'#f4f0e8');d=ImageDraw.Draw(out);d.text((20,12),'SGODOT-448 · 左翼实际几何与长凳净空（俯视，单位 m）',font=f(25),fill='#302c28')
occupancy=json.loads((Q/'decor-occupancy.json').read_text())
for k,look in enumerate(['a','b']):
 ox=25+k*725;oz=100;scale=195
 def pt(x,z):return (int(ox+(x+3.3)*scale),int(oz+(z+1.85)*scale))
 def rect(x0,z0,x1,z1,**kw):d.rectangle([pt(x0,z0),pt(x1,z1)],**kw)
 d.text((ox,62),'kitchen_wing_'+look,font=f(22),fill='#302c28')
 for x in range(5,10):
  for y in range(15,19):
   a=x*.65-6.175;b=-(y+1)*.65+10.725
   rect(a,b,a+.65,b+.65,outline='#d5cdbf',width=1)
   d.text(pt(a+.02,b+.02),f'({x},{y})',font=f(15),fill='#827764')
 for row in occupancy['levels']['8']['kitchen_wing_'+look]:
  if row['current_server_block'] is None:
   x,y=row['cell'];a=x*.65-6.175;b=-(y+1)*.65+10.725
   rect(a,b,a+.65,b+.65,fill='#ffe0a3',outline='#d0aa60',width=1)
 d.rectangle([pt(-2.925,-.825),pt(-1.625,.825)],fill='#d4ebd3',outline='#2e7b47',width=3)
 d.rectangle([pt(-2.925,.325),pt(-1.625,.975)],outline='#2e7b47',width=3)
 doc,buf=load_glb(ROOT/'assets/farm/art'/('kitchen_wing_'+look+'.glb'));pr=doc['meshes'][0]['primitives'][0];v=accessor(doc,buf,pr['attributes']['POSITION']);ids=[x[0] for x in accessor(doc,buf,pr['indices'])]
 layer=Image.new('RGBA',out.size,(0,0,0,0));ld=ImageDraw.Draw(layer)
 for i in range(0,len(ids),3):ld.polygon([pt(v[j][0],v[j][2]) for j in ids[i:i+3]],fill=(95,121,145,100),outline=(54,80,101,150))
 out=Image.alpha_composite(out.convert('RGBA'),layer).convert('RGB');d=ImageDraw.Draw(out)
 rect(-2.835,-.24,-1.715,.24,fill='#b7844b',outline='#755631',width=3)
 d.text(pt(-2.79,-.11),'原长凳',font=f(18),fill='white')
 d.text(pt(-2.90,.57),'前后各留0.5m',font=f(17),fill='#28633a')
 d.line([pt(-3.3,-1.625),pt(.1,-1.625)],fill='#a38c77',width=3)
 d.text(pt(-3.25,-1.79),'原后篱笆线',font=f(16),fill='#75604d')
d.text((20,720),'绿色：长凳格 + 前后0.5m保护区，以及前一排(5,15)/(6,15)；蓝灰：实际左翼几何投影。',font=f(21),fill='#302c28')
d.text((20,758),'长凳世界范围 X[3.25,4.55] / Z[-11.05,-10.40]；保护区 Z[-11.55,-9.90]。',font=f(21),fill='#302c28')
d.text((20,796),'黄色：当前仍可摆装饰的7格，需程序另做禁摆（a/b、Lv8/Lv15一致）：',font=f(21),fill='#7c571b')
d.text((20,834),'(5,17), (5,18), (6,18), (7,16), (7,17), (7,18), (8,18)。本次不改导航/服务端。',font=f(21),fill='#7c571b')
d.text((20,887),'数据：GLB三角面投影 + 原服务端yardBlock()；原点=house(6.175,0,-10.725)。赵云',font=f(18),fill='#50483d');out.save(OUT/'SGODOT-448_clearance_plan.png',optimize=True)
for name in ['clearance-validation.json','render-validation.json','cold-import-validation.json','decor-occupancy.json','actor-height.json','baseline.json']:
 shutil.copy2(Q/name,OUT/name)
shutil.copy2(ROOT/'output/homestead-439/asset-validation.json',OUT/'439-asset-validation.json')
shutil.copy2(ROOT/'output/homestead-440/validation.json',OUT/'440-asset-validation.json') if (ROOT/'output/homestead-440/validation.json').exists() else None
print('Review sheets',len(list(OUT.glob('*.png'))))
