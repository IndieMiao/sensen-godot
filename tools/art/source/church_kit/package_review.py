from pathlib import Path
import json,hashlib
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
ROOT=Path(__file__).resolve().parents[4];KIT=ROOT/'assets/rooms/_shared/church_kit';OUT=ROOT/'output/church-kit-427-v11';CAP=OUT/'captures';DOC=ROOT/'docs/design/church-kit-427-v11-2026-11-06';DOC.mkdir(parents=True,exist_ok=True)
m=json.loads((KIT/'kit_manifest.json').read_text());g=json.loads((OUT/'geometry-validation.json').read_text());r=json.loads((CAP/'godot-validation.json').read_text());assert g['passed'] and r['passed']
font=lambda size:ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',size)
labels={'wall_door_2m':'入口门墙（双木门）','wall_straight_2m':'直墙','wall_corner_2m':'转角墙','wall_pointed_2m':'尖拱窗墙','wall_rose_2m':'玫瑰窗墙','roof_band_2m':'上方拱顶带','floor_tile_2m':'石地面模块','beam_2m':'木梁','steps_2m':'三级台阶模块','pointed_glass':'尖拱彩窗玻璃','rose_glass':'玫瑰窗玻璃','rose_frame':'玫瑰窗石框','wood_pew':'木长椅','altar_table':'祭坛桌与蜡烛','sanctuary_steps':'原大祭坛台阶','iron_chandelier':'铁艺吊灯','pipe_organ':'管风琴','flower_pedestal':'花架','grass_surround':'草地衬底（辅助）'}
canvas=Image.new('RGB',(1500,1495),'#F0EBDD');d=ImageDraw.Draw(canvas)
d.text((16,10),'黄忠 · 可复用教堂套件 v1.1｜19 件 · 2 m 结构模数 · 参照人 H=1.745 m',font=font(26),fill='#344339')
d.text((16,44),'每格独立取景，模型保持原尺寸；玻璃与石框分件，换色只需替换色板材质。',font=font(18),fill='#53604D')
for i,(name,row) in enumerate(m['assets'].items()):
 x=(i%4)*375;y=75+(i//4)*282
 d.text((x+10,y),f'{i+1:02d} {labels[name]}',font=font(20),fill='#344339')
 canvas.paste(Image.open(CAP/('catalog_'+name+'.png')).convert('RGB'),(x+7,y+27))
 dims=' × '.join(f'{v:.2f}' for v in row['dimensions_m'])
 d.text((x+10,y+248),f'{dims} m · {row["triangles"]:,} 面',font=font(15),fill='#344339')
 d.text((x+10,y+266),name,font=font(11),fill='#657160')
x=3*375+12;y=75+4*282+24
for j,line in enumerate(['标准段：2 m；墙高：4.8 m','转角：每臂 1 m，正交旋转','8 m 边长 = 1 + 2 + 2 + 2 + 1','19 件独立网格：30,552 面','示例：4 张长椅 / 无迷宫','原教堂71文件哈希不变','示例只作审阅，不交游戏 layout']):d.text((x,y+j*30),line,font=font(14),fill='#344339')
meta=PngImagePlugin.PngInfo();meta.add_text('Author','黄忠 / 5281cd25-6a49-4df8-9802-f3e534956e80');meta.add_text('Status','Reusable kit and review-only8x8 example; not a new game location')
prefix='SGODOT-427_church_kit_v1.1_';canvas.save(DOC/(prefix+'catalogue.png'),pnginfo=meta)
for raw,dest in [('example_360','example_360'),('example_overview','example_overview')]:Image.open(CAP/(raw+'.png')).save(DOC/(prefix+dest+'.png'),pnginfo=meta)
image=Image.open(CAP/'palette_swap.png').convert('RGB');sheet=Image.new('RGB',(1000,970),'#F0EBDD');sheet.paste(image,(0,60));dr=ImageDraw.Draw(sheet);dr.text((18,8),'黄忠 · 同一窗件 / 同一灯光 / 只换 palette_texture',font=font(24),fill='#344339');dr.text((100,36),'Classic（原蓝金）',font=font(18),fill='#344339');dr.text((600,36),'Meadow（灰绿淡紫）',font=font(18),fill='#344339');sheet.save(DOC/(prefix+'palette_swap.png'),pnginfo=meta)
door=Image.open(CAP/'door_front.png').convert('RGB');sheet=Image.new('RGB',(720,1060),'#F0EBDD');sheet.paste(door,(0,60));dr=ImageDraw.Draw(sheet)
dr.text((16,8),'黄忠 · wall_door_2m · 2 × 4.8 m / 1 surface',font=font(23),fill='#344339')
dr.text((16,38),'门洞 1.40 × 2.60 m · 木门无字无图案 · 人高 1.745 m',font=font(18),fill='#344339');sheet.save(DOC/(prefix+'door_front.png'),pnginfo=meta)
cold=json.loads((OUT/'cold-import-validation.json').read_text());assert cold['passed']
validation={'cold_import':cold,'author':'黄忠','virtual_user_id':m['virtual_user_id'],'geometry':g,'godot':r,'scope':'Only modular church kit. Example is a non-shipping isolated review script; no new church layout, POI or runtime scene.'}
(DOC/(prefix+'validation.json')).write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(DOC.glob(prefix+'*'))],indent=2)+'\n')
print('PACKAGED',len(list(DOC.glob(prefix+'*'))))
