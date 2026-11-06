from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];O=ROOT/'output/alcatraz-tower-color-424';C=O/'captures';D=ROOT/'docs/design/alcatraz-tower-color-424-2026-11-06';D.mkdir(parents=True,exist_ok=True)
font=lambda n:ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
meta=PngImagePlugin.PngInfo();meta.add_text('Author','黄忠 / 5281cd25-6a49-4df8-9802-f3e534956e80')
report=json.loads((C/'godot-validation.json').read_text());geometry=json.loads((O/'geometry-validation.json').read_text());assert report['passed'] and geometry['passed'];prefix='SGODOT-424_tower_color_v1_'
canvas=Image.new('RGB',(1464,570),'#F2EDDF');dr=ImageDraw.Draw(canvas)
dr.text((15,9),'黄忠 · 双塔对齐整岛正式配色｜bf0c31b1 原场景、原光照、原摆位',font=font(23),fill='#34444A')
for i,(name,label) in enumerate([('summit_before','调整前'),('summit_after','调整后')]):
 dr.text((15+i*744,45),label,font=font(20),fill='#34444A');canvas.paste(Image.open(C/(name+'.png')),(i*744,76))
dr.text((15,541),'三者同框审阅宽度60.61 m（游戏20.16 m上限未改）；配对取景在塔以外的像素差为0',font=font(18),fill='#34444A')
canvas.save(D/(prefix+'summit_before_after.png'),pnginfo=meta)
canvas=Image.new('RGB',(1464,888),'#F2EDDF');dr=ImageDraw.Draw(canvas);dr.text((15,8),'黄忠 · 同配色 / 原55 m切档｜近远几何沿用已验收版本',font=font(23),fill='#34444A')
for i,(name,label) in enumerate([('alc_lighthouse_54m','灯塔 54 m 近档'),('alc_lighthouse_56m','灯塔 56 m 远档'),('alc_watertower_54m','水塔 54 m 近档'),('alc_watertower_56m','水塔 56 m 远档')]):
 x=i*368;dr.text((x+8,43),label,font=font(18),fill='#34444A');canvas.paste(Image.open(C/(name+'.png')),(x,78))
canvas.save(D/(prefix+'lod_54_56.png'),pnginfo=meta)
im=Image.open(C/'native_summit_after.png');im.save(D/(prefix+'native_20m_after.png'),pnginfo=meta)
colour=json.loads((SRC/'colour-map.json').read_text());validation={'author':'黄忠','virtual_user_id':colour['virtual_user_id'],'colour_map':colour,'geometry':geometry,'godot':report,'fixture':json.loads((O/'fixture.json').read_text()),'scope':'Tower RGB-only recolour and separate museum sign update; desktopMobile/Vulkan isolated review, not phone/whole-game acceptance.'}
(D/(prefix+'validation.json')).write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
(D/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(D.glob(prefix+'*'))],indent=2)+'\n')
print('TOWER_PACKAGED')
