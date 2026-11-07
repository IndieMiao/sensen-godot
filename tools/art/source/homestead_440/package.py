"""Label actual farm captures; no scaling or retouching of rendered imagery."""
from pathlib import Path
import json,shutil
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent
OUT=ROOT/'output/homestead-440';CAP=OUT/'captures';DOC=ROOT/'docs/design/homestead-440';DOC.mkdir(parents=True,exist_ok=True)
font='/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc'
def f(n):return ImageFont.truetype(font,n)
report=json.loads((CAP/'render-validation.json').read_text());metrics={a['name']:a for a in report['captures']}
manifest=json.loads((SRC/'manifest.json').read_text())
assert all(x['passed'] for x in report['checks'])
for stale in ['main-block-default-preview.png','main-block-close-preview.png']:(DOC/stale).unlink(missing_ok=True)
for annotated in [False,True]:
 board=Image.new('RGB',(1104,976),'#f4f1e8');d=ImageDraw.Draw(board)
 d.text((16,10),'SGODOT-440 · Lv15 整栋第一版 · 木作 / 石作',font=f(25),fill='#283c36')
 d.text((16,46),'实际农场 · 同机位同光照 · 每列原始 360 × 800 · 439 已定接口，最终几何待核同款',font=f(17),fill='#40594d')
 for i,(name,label) in enumerate([('current-default','现房 Cottage'),('lv15-a-default','Lv15 a 木作'),('lv15-b-default','Lv15 b 石作')]):
  x=8+i*368;y=110;im=Image.open(CAP/(name+'.png')).convert('RGB');assert im.size==(360,800);board.paste(im,(x,y))
  d.text((x+6,78),label,font=f(21),fill='#263c32')
  top=metrics[name]['highest_pixel'];py=y+top[1]
  if annotated:
   d.line((x+12,y+150,x+348,y+150),fill='#eb6653',width=2)
   d.text((x+12,y+126),'y=150 上限',font=f(15),fill='#d65340')
   d.ellipse((x+top[0]-4,py-4,x+top[0]+4,py+4),fill='#fef1a5',outline='#334b32',width=1)
   d.line((x+top[0]+4,py,x+278,py),fill='#263c32',width=1)
   d.text((x+235,py-23),f'y={top[1]:.1f}',font=f(16),fill='#263c32')
  d.text((x+6,918),f'模型高 {metrics[name]["model_height_m"]:.4f} m · 最高点 y={top[1]:.1f}',font=f(16),fill='#344d3f')
  d.text((x+6,943),f'原烟雾全周期保守边界 y≥{metrics[name]["smoke_full_cycle_top_bound_px"]:.1f}',font=f(15),fill='#344d3f')
 board.save(DOC/('height-review.png' if annotated else 'default-review.png'))
close=Image.new('RGB',(744,930),'#f4f1e8');d=ImageDraw.Draw(close)
d.text((12,8),'门牌视角 · 木作 a / 石作 b',font=f(24),fill='#283c36')
d.text((12,41),'门、路、三牌不移；长凳(3,16)、左灌木左移为隔离接入预览。',font=f(16),fill='#40594d')
for i,v in enumerate(['a','b']):
 x=8+i*368;close.paste(Image.open(CAP/('lv15-'+v+'-close.png')),(x,82))
 d.text((x+8,889),'暖木门廊 / 左翼' if v=='a' else '石拱门廊 / 左翼',font=f(18),fill='#283c36')
close.save(DOC/'door-sign-review.png')
for name in ['current-default','lv15-a-default','lv15-b-default','lv15-a-close','lv15-b-close']:shutil.copy2(CAP/(name+'.png'),DOC/(name+'.png'))
for src,name in [(OUT/'glb-validation.json','glb-validation.json'),(CAP/'render-validation.json','render-validation.json'),(OUT/'cold-import.json','cold-import.json'),(OUT/'android/smoke.json','android-smoke.json')]:
 if src.exists():shutil.copy2(src,DOC/name)
print(DOC)
