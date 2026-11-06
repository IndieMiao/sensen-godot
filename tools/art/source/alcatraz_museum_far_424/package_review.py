from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
import json,hashlib
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/alcatraz-museum-far-424';CAP=OUT/'captures';DOC=ROOT/'docs/design/alcatraz-museum-far-424-2026-11-06/v1.1';DOC.mkdir(parents=True,exist_ok=True)
font=lambda size:ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',size)
meta=PngImagePlugin.PngInfo();meta.add_text('Author','黄忠 / 5281cd25-6a49-4df8-9802-f3e534956e80');meta.add_text('Status','v1.1 text-free pictogram bf0c31b1')
for mode in ['full','front','mobile_wide','mobile_default']:
 left=Image.open(CAP/(mode+'_54m.png')).convert('RGB');right=Image.open(CAP/(mode+'_56m.png')).convert('RGB')
 canvas=Image.new('RGB',(left.width*2+24,left.height+104),'#F0ECE2');draw=ImageDraw.Draw(canvas)
 draw.text((12,8),'黄忠 · SGODOT-424 主楼远档 v1.1｜无文字图形招牌 bf0c31b1',font=font(19),fill='#34444A')
 draw.text((12,42),'54 m · 近档 7,869 面',font=font(18),fill='#34444A');draw.text((left.width+24,42),'56 m · 远档 2,205 面',font=font(18),fill='#34444A')
 canvas.paste(left,(0,78));canvas.paste(right,(left.width+24,78))
 draw.text((12,left.height+80),'同方向 / 同正交宽度；沿视线移动2 m，Godot按55 m切档；bf0c31b1无文字招牌',font=font(15),fill='#34444A')
 canvas.save(DOC/('SGODOT-424_museum_far_v1.1_'+mode+'_54_56.png'),pnginfo=meta)
geometry=json.loads((OUT/'geometry-validation.json').read_text());godot=json.loads((CAP/'godot-validation.json').read_text());assert geometry['passed'] and godot['passed']
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','status':'Text-free lighthouse sign matched exactly to bf0c31b1; draft pending art review.','geometry':geometry,'godot':godot}
(DOC/'SGODOT-424_museum_far_v1.1_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
files=sorted(DOC.glob('SGODOT-*'));(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in files],indent=2)+'\n');print('PACKAGED',len(files))
