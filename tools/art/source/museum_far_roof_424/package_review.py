from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
import json,hashlib
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/museum-far-roof-424';CAP=OUT/'captures'
DOC=ROOT/'docs/design/museum-far-roof-424-2026-11-06';DOC.mkdir(parents=True,exist_ok=True)
geometry=json.loads((OUT/'geometry-validation.json').read_text());godot=json.loads((CAP/'godot-validation.json').read_text());assert geometry['passed'] and godot['passed']
font=lambda size:ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',size)
meta=PngImagePlugin.PngInfo();meta.add_text('Author','黄忠 / 5281cd25-6a49-4df8-9802-f3e534956e80');meta.add_text('Near reference','ebce1cec1d508d3b4b2de496a0f9c50b644e88d7 / #835')
prefix='SGODOT-424_museum_far_roof_v1_'
for mode in ['full','mobile_default']:
 left=Image.open(CAP/(mode+'_54m.png')).convert('RGB');right=Image.open(CAP/(mode+'_56m.png')).convert('RGB')
 canvas=Image.new('RGB',(left.width*2+24,left.height+112),'#F0ECE2');d=ImageDraw.Draw(canvas)
 d.text((12,8),'黄忠 · 主楼屋顶同步｜#835 ebce1cec · 55 m 自动切档',font=font(19),fill='#34444A')
 d.text((12,42),'54 m · 近档 8,757 面',font=font(18),fill='#34444A');d.text((left.width+24,42),'56 m · 远档 2,239 面',font=font(18),fill='#34444A')
 canvas.paste(left,(0,78));canvas.paste(right,(left.width+24,78))
 d.text((12,left.height+82),'同方向 / 同正交宽度；远档平面天窗，通风口按新尺寸/颜色；无字图形牌保留',font=font(14),fill='#34444A')
 canvas.save(DOC/(prefix+mode+'_54_56.png'),pnginfo=meta)
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','geometry':geometry,'godot':godot,'near_parent':'ebce1cec1d508d3b4b2de496a0f9c50b644e88d7','scope':'Only far roof replacement; near/model imports/layout unchanged. Same-camera and54/56m actual visibility_range captures.'}
(DOC/(prefix+'validation.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(DOC.glob(prefix+'*'))],indent=2)+'\n')
print('PACKAGED',len(list(DOC.glob(prefix+'*'))))
