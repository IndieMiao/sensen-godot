"""Package full-resolution game captures and signed verification evidence."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[3]
OUT = ROOT / 'output/skin-325-v1'
DOC = ROOT / 'docs/design/skin-325-B-2026-11-03'
DOC.mkdir(parents=True, exist_ok=True)
godot = json.loads((OUT/'captures/godot-validation.json').read_text())
preservation = json.loads((OUT/'preservation-validation.json').read_text())
assert godot['passed'] and preservation['passed']
assert godot['renderer']['method'] == 'mobile'
assert 'ERROR:' not in (OUT/'render.log').read_text()
font = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
title = ImageFont.truetype(font,31)
label = ImageFont.truetype(font,25)
small = ImageFont.truetype(font,21)
prefix = 'SGODOT-325_skin_B_v1_'
files = []
for key, name in [('N1','明亮酒店'),('N2','诊所')]:
    board = Image.new('RGB',(1472,1750),'#F5F6F5')
    draw = ImageDraw.Draw(board)
    draw.text((18,12),'SGODOT-325 / '+key+' B「'+name+'」/ 正式资源 v1',font=title,fill='#263E42')
    draw.text((18,61),'A 基础款',font=label,fill='#34494B')
    draw.text((770,61),'B '+name,font=label,fill='#34494B')
    for x, variant in [(0,'A'),(752,'B')]:
        image = Image.open(OUT/'captures'/(key+'_'+variant+'_default.png')).convert('RGB')
        assert image.size == (720,1600)
        board.paste(image,(x,105))
    draw.text((18,1712),'43° 同机位 / 每幅 720 × 1600 / 人物 H=1.745 m / '+('站在地毯上' if key=='N1' else '站在十字上'),font=small,fill='#34494B')
    draw.text((1310,1712),'【黄忠】',font=small,fill='#34494B')
    path = DOC/(prefix+key+'_compare.jpg')
    board.save(path,quality=94,subsampling=0,optimize=True)
    files.append(path)
    source = Image.open(OUT/'captures'/(key+'_B_overview.png')).convert('RGB')
    assert source.size == (1440,1320)
    board = Image.new('RGB',(1440,1440),'#F5F6F5')
    board.paste(source,(0,80))
    draw = ImageDraw.Draw(board)
    draw.text((18,12),'SGODOT-325 / '+key+' B「'+name+'」/ 全景 v1',font=title,fill='#263E42')
    draw.text((18,1407),'43° / 原布局、家具、座位与碰撞保持 / 门头不烤字',font=small,fill='#34494B')
    draw.text((1280,1407),'【黄忠】',font=small,fill='#34494B')
    path = DOC/(prefix+key+'_overview.jpg')
    board.save(path,quality=94,subsampling=0,optimize=True)
    files.append(path)
report = {'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
          'approval':'C61 / Plane 325 d1e61761; palette v0.1 / mock 3daac452',
          'source_preservation':preservation,'palette':json.loads((OUT/'palette-report.json').read_text()),'godot':godot}
path = DOC/(prefix+'validation.json')
path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
files.append(path)
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,
    'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'author':'黄忠',
    'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in files],ensure_ascii=False,indent=2)+'\n')
print(DOC)
