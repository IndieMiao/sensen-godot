"""Package independent model review; opening-shot acceptance waits for v2 coordinates."""
from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'output/alcatraz-far-424';CAP=OUT/'captures'
DOC=ROOT/'docs/design/alcatraz-far-424-2026-11-06';DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-424_far_v1_';FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
titles={'lighthouse_lod_scale':'灯塔近 / 远档 · 15 m','watertower_lod_scale':'水塔近 / 远档 · 12 m','towers_player_175':'两塔与 1.75 m 人物 · 原尺寸','scenic_cards':'三件远景轮廓 · 独立模型预看，非开场摆位'}
for name,title in titles.items():
 im=Image.open(CAP/(name+'.png')).convert('RGB');d=ImageDraw.Draw(im)
 d.rounded_rectangle((16,14,min(im.width-16,1050),60),10,fill='#F9F5E9');d.text((30,20),'黄忠 · SGODOT-424 · '+title,font=ImageFont.truetype(FONT,24),fill='#314D55')
 d.text((22,im.height-33),'Godot Mobile / Vulkan · 坐标与开场验图待 v2 对齐',font=ImageFont.truetype(FONT,18),fill='#314D55')
 im.save(DOC/(PREFIX+name+'.png'))
g=json.loads((OUT/'geometry-validation.json').read_text());r=json.loads((CAP/'godot-validation.json').read_text())
assert g['passed'] and r['passed']
v={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','scope':'independent seven-asset review; placement and opening bridge shot pending v2 coordinate confirmation','geometry':g,'godot':r,'model_validation_passed':True,'opening_review_complete':False}
(DOC/(PREFIX+'validation.json')).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
items=[]
for p in sorted(DOC.glob(PREFIX+'*')):
 row={'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
 if p.suffix=='.png':row['size']=list(Image.open(p).size);assert max(row['size'])<=1600
 items.append(row)
(DOC/'media-manifest.json').write_text(json.dumps(items,ensure_ascii=False,indent=2)+'\n');print('Prepared',len(items),'model-review files')
