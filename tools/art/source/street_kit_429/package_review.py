from pathlib import Path
import json,hashlib
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'output/street-kit-429';CAP=OUT/'captures'
KIT=ROOT/'assets/landmarks/_shared/street_kit';DOC=ROOT/'docs/design/street-kit-429-2026-11-06/v1.1';DOC.mkdir(parents=True,exist_ok=True)
m=json.loads((KIT/'kit_manifest.json').read_text());g=json.loads((OUT/'geometry-validation.json').read_text());r=json.loads((CAP/'godot-validation.json').read_text());cold=json.loads((OUT/'cold-import-validation.json').read_text())
assert g['passed'] and r['passed'] and cold['passed']
font=lambda n:ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
labels={'lamp_single':'单头路灯','lamp_double':'双头路灯','bench_wood':'木长椅','bench_stone':'石长椅','railing_straight_2m':'2 m 直栏杆','railing_endpost':'栏杆端柱','railing_corner':'转角栏杆','bollard':'矮柱','planter_square':'方花槽','planter_long':'长花槽','litter_bin':'垃圾桶','sign_standing':'立式空白指示牌','sign_wall':'挂墙空白指示牌','bicycle_rack':'自行车架','umbrella_table':'遮阳伞桌','drinking_fountain':'饮水台'}
canvas=Image.new('RGB',(1500,1400),'#F0EBDD');d=ImageDraw.Draw(canvas)
d.text((15,10),'黄忠 · 街道家具套件 v1.1｜16 件 · 5,970 面 · 2 m 摆放模数',font=font(28),fill='#38493C')
d.text((15,49),'每格独立取景 / 原尺寸 / 参照人 H=1.745 m；全部 1 surface 顶点色，无贴图。',font=font(19),fill='#53604D')
for i,(name,row) in enumerate(m['assets'].items()):
 x=i%4*375;y=85+i//4*320
 d.text((x+10,y),f'{i+1:02d} {labels[name]}',font=font(21),fill='#38493C')
 canvas.paste(Image.open(CAP/('catalog_'+name+'.png')).convert('RGB'),(x+7,y+27))
 dims=' × '.join(f'{v:.2f}' for v in row['dimensions_m'])
 d.text((x+10,y+280),f'{dims} m · {row["triangles"]} 面',font=font(16),fill='#38493C')
 d.text((x+10,y+302),name,font=font(12),fill='#63705E')
d.text((15,1370),'宽X × 高Y × 深Z；挂墙牌背面中心原点，转角以弯点接两条 1 m 臂。示例只作审阅，不交游戏 layout。',font=font(17),fill='#53604D')
metadata=PngImagePlugin.PngInfo();metadata.add_text('Author','黄忠 / '+m['virtual_user_id']);metadata.add_text('Scope','SGODOT-429 reusable street furniture; review-only plaza, no game layout')
prefix='SGODOT-429_street_kit_v1.1_';canvas.save(DOC/(prefix+'catalogue.png'),pnginfo=metadata)
for name in ['example_360','example_overview']:
 Image.open(CAP/(name+'.png')).save(DOC/(prefix+name+'.png'),pnginfo=metadata)
# Exact same camera/light: crop old raw panels out of the committed v1 catalogue.
old=Image.open(DOC.parent/'SGODOT-429_street_kit_v1_catalogue.png').convert('RGB')
compare=Image.new('RGB',(760,650),'#F0EBDD');dr=ImageDraw.Draw(compare)
dr.text((16,8),'黄忠 · 木色 v1 / v1.1 · 同机位同灯光',font=font(24),fill='#38493C')
dr.text((80,42),'v1',font=font(18),fill='#53604D');dr.text((460,42),'v1.1',font=font(18),fill='#53604D')
for row,(name,index) in enumerate([('bench_wood',2),('umbrella_table',14)]):
 x=index%4*375+7;y=85+index//4*320+27
 compare.paste(old.crop((x,y,x+360,y+250)),(10,75+row*260))
 compare.paste(Image.open(CAP/('catalog_'+name+'.png')).convert('RGB'),(390,75+row*260))
dr.text((16,607),'顶点色 sRGB：木 #A3815D / 亮 #B89972 / 暗 #795F47',font=font(18),fill='#38493C')
compare.save(DOC/(prefix+'wood_comparison.png'),pnginfo=metadata)
wood=json.loads((OUT/'wood-colour-validation.json').read_text());assert wood['passed']
validation={'wood_colour':wood,'author':'黄忠','virtual_user_id':m['virtual_user_id'],'geometry':g,'godot':r,'cold_import':cold,'scope':'Only new street-kit files; plaza ground pinned to #830 is an isolated review dependency, not delivered runtime integration.'}
(DOC/(prefix+'validation.json')).write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(DOC.glob(prefix+'*'))],indent=2)+'\n')
print('PACKAGED',len(list(DOC.glob(prefix+'*'))))
