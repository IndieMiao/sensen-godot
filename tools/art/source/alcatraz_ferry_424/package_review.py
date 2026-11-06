from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
import hashlib,json,shutil,numpy as np
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/alcatraz-ferry-424';DOC=ROOT/'docs/design/alcatraz-ferry-424-2026-11-06';CAP=OUT/'captures';DOC.mkdir(parents=True,exist_ok=True)
prefix='SGODOT-424_ferry_gull_v1_';font=lambda size:ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',size)
meta=PngImagePlugin.PngInfo();meta.add_text('Author','黄忠 / 5281cd25-6a49-4df8-9802-f3e534956e80');meta.add_text('Task','SGODOT-424 ferry and gull v1')
for name,caption in [('opening_360',None),('dock_ferry_detail','黄忠 · 码头全船补充视角（不是开场）｜原尺寸 25 m｜#792 b16c3198 白模'),('near_far','黄忠 · 同比例近远档｜上：ferry_far 1,480 面｜下：ferry 5,144 面｜55 m 切档'),('gull_poses','黄忠 · 海鸥单网格 284 面｜左：stand｜中：preen｜右：spread｜原地静态形态')]:
 im=Image.open(CAP/(prefix+name+'.png')).convert('RGB')
 if caption:
  canvas=Image.new('RGB',(im.width,im.height+58),'#F1EDE1');canvas.paste(im,(0,0));ImageDraw.Draw(canvas).text((20,im.height+13),caption,font=font(22),fill='#34444A');im=canvas
 im.save(DOC/(prefix+name+'.png'),pnginfo=meta)
geometry=json.loads((OUT/'geometry-validation.json').read_text());godot=json.loads((CAP/'godot-validation.json').read_text());fixture=json.loads((OUT/'fixture.json').read_text())
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','geometry':geometry,'godot':godot,'fixture':fixture,'limits':'Desktop Vulkan Mobile review in pinned art blockout. No gameplay/server/Android or physical-device FPS acceptance.'}
opening=godot['captures'][prefix+'opening_360'];assert opening['triangles']<=80000 and opening['draws']+opening['shadow_draws']<=60
report['opening_budget_passed']=True
(DOC/(prefix+'validation.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
(DOC/'media-manifest.json').write_text(json.dumps([{'file':f.name,'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted(DOC.glob(prefix+'*'))],ensure_ascii=False,indent=2)+'\n')
print('PACKAGED',len(list(DOC.glob(prefix+'*'))))
