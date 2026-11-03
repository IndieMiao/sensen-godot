"""White-background measured asset sheet and real-player 43-degree scale view."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
OUT=ROOT/'output/culture-props-323';DOC=ROOT/'docs/design/poi-culture-props-323-2026-11-03'
DOC.mkdir(parents=True,exist_ok=True)
manifest=json.loads((ROOT/'assets/rooms/poi_culture_hall/props/prop_manifest.json').read_text())
revision=manifest['revision']
if revision!='v1':DOC=DOC/revision;DOC.mkdir(parents=True,exist_ok=True)
reports={name:json.loads((OUT/file).read_text()) for name,file in [
    ('geometry','geometry-validation.json'),('source','source-validation.json'),('godot','captures/godot-validation.json')]}
assert all(v['passed'] for v in reports.values())
assert 'ERROR:' not in (OUT/'render.log').read_text()
names={'display_cabinet':'玻璃展柜 ×2','exhibit_plinth':'象牙白展台',
    'artwork_set':'六画组合（2 排 × 3 列）','case_exhibits_1':'玻璃柜 1 展品组合（3 件）','case_exhibits_2':'玻璃柜 2 展品组合（3 件）',
    'exhibit_shallow_bowl':'浅陶碗','exhibit_terracotta_jar':'陶罐','exhibit_leaf_fossil':'叶形化石',
    'exhibit_shell_fragment':'扇形化石','exhibit_fossil_rock':'岩块标本','exhibit_spiral_fossil':'平放螺旋化石',
    'exhibit_ammonite':'直立菊石','floor_mosaic':'同心圆石拼花','name_sign':'空白浅木招牌'}
font='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
title=ImageFont.truetype(font,38);label=ImageFont.truetype(font,26);small=ImageFont.truetype(font,23)
prefix='SGODOT-323_props_'+revision+'_';files=[]
board=Image.new('RGB',(2560,1700),'white');draw=ImageDraw.Draw(board)
draw.text((24,15),'SGODOT-323 / N3 文化大厅新做件 / '+revision+' / 实际 GLB 尺寸',font=title,fill='#283D34')
draw.text((24,70),f"8 个交付组 / 展柜复用 2 次 / {manifest['unique_triangles']:,} 独立面；摆放 {manifest['placed_triangles']:,} 面、11 surface / 组合内原子件各 ≤600 面",font=label,fill='#3C5146')
for i,spec in enumerate(manifest['assets']):
    x=(i%4)*640+20;y=(i//4)*760+118
    image=Image.open(OUT/'captures'/(spec['name']+'.png')).convert('RGB');assert image.size==(600,600)
    board.paste(image,(x,y))
    draw.text((x,y+608),names[spec['name']],font=label,fill='#283D34')
    dims=reports['geometry']['assets'][spec['name']]['dimensions_m']
    draw.text((x,y+648),'宽 %.3f × 高 %.3f × 深 %.3f m'%tuple(dims),font=small,fill='#3C5146')
    draw.text((x,y+685),'%d 三角面 / %d surface'%(spec['triangles'],spec['surfaces']),font=small,fill='#3C5146')
draw.text((24,1660),'各格独立取景，不同比例；尺寸来自导出顶点。画组与展品组的位置已烘入网格，不再分别摆子件。',font=small,fill='#3C5146')
draw.text((2400,1660),'【黄忠】',font=small,fill='#283D34')
path=DOC/(prefix+'dimensions.jpg');board.save(path,quality=94,subsampling=0,optimize=True);files.append(path)
image=Image.open(OUT/'captures/scale_43deg.png').convert('RGB');assert image.size==(1800,1800)
board=Image.new('RGB',(1800,1940),'white');board.paste(image,(0,90));draw=ImageDraw.Draw(board)
draw.text((24,15),'SGODOT-323 / N3 新做件 / 43° 玩家比例图 / '+revision,font=title,fill='#283D34')
draw.text((24,1898),'玩家 H=1.745 m；白底摆件台仅作比例审阅，不是赵云的整间布局。',font=label,fill='#3C5146')
draw.text((1635,1898),'【黄忠】',font=label,fill='#283D34')
path=DOC/(prefix+'scale_43deg.jpg');board.save(path,quality=94,subsampling=0,optimize=True);files.append(path)
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','manifest':manifest,**reports}
path=DOC/(prefix+'validation.json');path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');files.append(path)
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,
    'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in files],ensure_ascii=False,indent=2)+'\n')
rows=['| 件名 | 数量 | 三角面/件 | Surface/件 | 实测宽 × 高 × 深 (m) |','|---|---:|---:|---:|---|']
for s in manifest['assets']:
    dims=reports['geometry']['assets'][s['name']]['dimensions_m']
    rows.append('| `%s` | %d | %d | %d | %.3f × %.3f × %.3f |'%(
        s['name'],s['quantity'],s['triangles'],s['surfaces'],*dims))
(DOC/'asset-table.md').write_text('# 实际导出资产统计\n\n'+'\n'.join(rows)+f"\n\n8 个组合 GLB：{manifest['unique_triangles']:,} 三角面 / 9 surface。按展柜两次、其余各一次摆放：{manifest['placed_triangles']:,} 三角面 / 11 surface。组合件总面数照实列出，原子件各不超过 600 面。\n")
print(DOC)
