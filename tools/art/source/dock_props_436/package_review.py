from pathlib import Path
import json,hashlib
from PIL import Image,ImageDraw,ImageFont,PngImagePlugin
ROOT=Path(__file__).resolve().parents[4];OUT=ROOT/'output/dock-props-436';CAP=OUT/'captures'
KIT=ROOT/'assets/landmarks/_shared/dock_props';DOC=ROOT/'docs/design/dock-props-436-2026-11-06/v1.1';DOC.mkdir(parents=True,exist_ok=True)
m=json.loads((KIT/'manifest.json').read_text());g=json.loads((OUT/'geometry-validation.json').read_text());r=json.loads((CAP/'godot-validation.json').read_text());cold=json.loads((OUT/'cold-import-validation.json').read_text())
assert g['passed'] and r['passed'] and cold['passed']
font=lambda n:ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',n)
labels=dict(zip(m['assets'],['售票亭','候船棚','登船跳板','救生圈架','平放绳卷','绑束绳卷','封口木箱','开口木箱','封口木桶','开口木桶','渔网挂架','小信标灯杆']))
canvas=Image.new('RGB',(1500,1090),'#F0EBDD');d=ImageDraw.Draw(canvas)
d.text((15,10),f"黄忠 · 码头小件 {m['revision']}｜12 件 · {m['unique_triangles']:,} 面 · 与426码头接口齐平",font=font(28),fill='#38493C')
d.text((15,49),'每格独立取景 / 原尺寸 / 参照人 H=1.745 m；全部 1 surface 顶点色，无贴图。',font=font(19),fill='#53604D')
for i,(name,row) in enumerate(m['assets'].items()):
 x=i%4*375;y=85+i//4*320
 d.text((x+10,y),f'{i+1:02d} {labels[name]}',font=font(21),fill='#38493C')
 canvas.paste(Image.open(CAP/('catalog_'+name+'.png')).convert('RGB'),(x+7,y+27))
 dims=' × '.join(f'{v:.2f}' for v in row['dimensions_m'])
 d.text((x+10,y+280),f'{dims} m · {row["triangles"]} 面',font=font(16),fill='#38493C')
 d.text((x+10,y+302),name,font=font(12),fill='#63705E')
d.text((15,1055),'宽X × 高Y × 深Z；Y朝上、底面中心原点。售票亭不写字；渡口示例只作审阅，不交游戏layout。',font=font(17),fill='#53604D')
metadata=PngImagePlugin.PngInfo();metadata.add_text('Author','黄忠 / '+m['virtual_user_id']);metadata.add_text('Scope','SGODOT-436 dock props; review-only ferry landing, no game layout')
prefix='SGODOT-436_dock_props_v1.1_';canvas.save(DOC/(prefix+'catalogue.png'),pnginfo=metadata)
for name in ['example_360']:
 Image.open(CAP/(name+'.png')).save(DOC/(prefix+name+'.png'),pnginfo=metadata)
validation={'revision':m['revision'],'author':'黄忠','virtual_user_id':m['virtual_user_id'],'geometry':g,'godot':r,'cold_import':cold,'dependencies':json.loads((OUT/'dependency-hashes.json').read_text()),'dock_connection':json.loads((ROOT/'tools/art/source/dock_props_436/dock_connection.json').read_text()),'scope':'12 new dock props only. Pinned426/430/432/434 plus ground are isolated review fixtures; no existing-file changes or game integration.'}
(DOC/(prefix+'validation.json')).write_text(json.dumps(validation,ensure_ascii=False,indent=2)+'\n')
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(DOC.glob(prefix+'*'))],indent=2)+'\n')
print('PACKAGED',len(list(DOC.glob(prefix+'*'))))
