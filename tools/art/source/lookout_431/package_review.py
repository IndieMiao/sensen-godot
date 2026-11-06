from pathlib import Path
import json,hashlib
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin,ImageOps
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'output/lookout-431';CAP=OUT/'captures'
KIT=ROOT/'assets/landmarks/_shared/street_kit';DOC=ROOT/'docs/design/lookout-431-2026-11-06/v1.1';DOC.mkdir(parents=True,exist_ok=True)
m=json.loads((KIT/'kit_manifest.json').read_text());g=json.loads((OUT/'geometry-validation.json').read_text());r=json.loads((CAP/'godot-validation.json').read_text());cold=json.loads((OUT/'cold-import-validation.json').read_text())
assert g['passed'] and r['passed'] and cold['passed']
font=lambda n:ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
labels={'lamp_single':'单头路灯','lamp_double':'双头路灯','bench_wood':'木长椅','bench_stone':'石长椅','railing_straight_2m':'2 m 直栏杆','railing_endpost':'栏杆端柱','railing_corner':'转角栏杆','bollard':'矮柱','planter_square':'方花槽','planter_long':'长花槽','litter_bin':'垃圾桶','sign_standing':'立式空白指示牌','sign_wall':'挂墙空白指示牌','bicycle_rack':'自行车架','umbrella_table':'遮阳伞桌','drinking_fountain':'饮水台','lookout_telescope':'新增 · 投币望远镜','lookout_railing_2m':'新增 · 2 m 观景栏杆','lookout_semicircle_2m':'新增 · 半圆观景台','lookout_compass_disc':'新增 · 无字方位圆盘','lookout_sheltered_bench':'新增 · 长凳与遮阳棚架'}
canvas=Image.new('RGB',(1500,1540),'#F0EBDD');d=ImageDraw.Draw(canvas)
d.text((15,8),'黄忠 · 街道 + 观景套件 v1.1｜21 件 · 8,285 面 · 2 m 模数',font=font(28),fill='#38493C')
d.text((15,46),'SGODOT-431 新增 17–21：2,329 面 / 5 surface；各件原尺寸，参照人 H=1.745 m，每格独立取景。',font=font(18),fill='#53604D')
for i,(name,row) in enumerate(m['assets'].items()):
 x=i%4*375;y=75+i//4*240
 d.text((x+10,y),f'{i+1:02d} {labels[name]}',font=font(19),fill='#35696A' if name.startswith('lookout_') else '#38493C')
 im=ImageOps.contain(Image.open(CAP/('catalog_'+name+'.png')).convert('RGB'),(360,180))
 canvas.paste(im,(x+(375-im.width)//2,y+24))
 dims=' × '.join(f'{v:.3f}' if name=='lookout_compass_disc' else f'{v:.2f}' for v in row['dimensions_m'])
 d.text((x+10,y+207),f'{dims} m · {row["triangles"]} 面',font=font(14),fill='#38493C')
 d.text((x+10,y+226),name,font=font(11),fill='#63705E')
y=75+5*240
d.text((385,y),'圆盘俯视（同件细节）',font=font(19),fill='#35696A')
im=ImageOps.contain(Image.open(CAP/'disc_detail.png').convert('RGB'),(195,195));canvas.paste(im,(465,y+28))
for j,line in enumerate(['半圆台：弦长 2 m，向外凸出 1 m','行走面 Y=0.12 m；两端配原有端柱','新旧上栏中心齐平，拼缝射线通过','新增件单件 180–728 面，均 1 surface','全部无字、无贴图；未改恶魔岛文件','6×4 m 观景角仅作审阅，不交 layout']):
 d.text((765,y+14+j*32),line,font=font(20),fill='#38493C')
metadata=PngImagePlugin.PngInfo();metadata.add_text('Author','黄忠 / '+m['virtual_user_id']);metadata.add_text('Scope','SGODOT-431 reusable lookout extension; review-only6x4 corner, no Alcatraz integration')
prefix='SGODOT-431_lookout_v1.1_';canvas.save(DOC/(prefix+'catalogue.png'),pnginfo=metadata)
Image.open(CAP/'example_360.png').save(DOC/(prefix+'example_360.png'),pnginfo=metadata)
validation={'author':'黄忠','virtual_user_id':m['virtual_user_id'],'geometry':g,'godot':r,'cold_import':cold,'scope':'Five new lookout assets appended to street kit. No Alcatraz files, scene layout or game integration changed.'}
(DOC/(prefix+'validation.json')).write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(DOC.glob(prefix+'*'))],indent=2)+'\n')
print('PACKAGED',len(list(DOC.glob(prefix+'*'))))
