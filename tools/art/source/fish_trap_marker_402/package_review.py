"""Signed native-pond review media, retaining the existing prompt issue and a labelled proposal."""
from pathlib import Path
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/trap-402'
DOC=ROOT/'docs/design/fish-trap-marker-402-2026-11-04';DOC.mkdir(parents=True,exist_ok=True)
reports={k:json.loads((OUT/path).read_text()) for k,path in [
    ('geometry','geometry-validation.json'),('source','source-validation.json'),('godot','captures/godot-validation.json')]}
assert all(r['passed'] for r in reports.values())
assert 'ERROR:' not in (OUT/'render.log').read_text() and 'NaN' not in (OUT/'render.log').read_text()
font='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
prefix='SGODOT-402_fish_trap_marker_v1_';files=[]
for name,title,note in [
    ('bank_43deg_comparison','A 款鱼笼浮标 · 塘边 43°','左：新鱼笼；右：原生抛竿浮漂 / 原生缩放'),
    ('marker_closeup','A 款鱼笼浮标 · 近景','500 面 / 1 surface / 水上 0.38 m / 笼宽 0.45 m / 近景 25°')]:
    image=Image.open(OUT/'captures'/(name+'.png')).convert('RGB');w,h=image.size
    heading=ImageFont.truetype(font,25 if w<1000 else 30);small=ImageFont.truetype(font,18 if w<1000 else 22)
    board=Image.new('RGB',(w,h+112),'#F7F5EF');board.paste(image,(0,65));draw=ImageDraw.Draw(board)
    draw.text((16,15),'SGODOT-402 / v1 / '+title,font=heading,fill='#4C4A3E')
    draw.text((16,h+80),note,font=small,fill='#4C4A3E');draw.text((w-106,h+80),'【黄忠】',font=small,fill='#4C4A3E')
    path=DOC/(prefix+name+'.jpg');board.save(path,quality=95,subsampling=0,optimize=True);files.append(path)
board=Image.new('RGB',(1472,1750),'#F7F5EF');draw=ImageDraw.Draw(board)
heading=ImageFont.truetype(font,30);label=ImageFont.truetype(font,23);small=ImageFont.truetype(font,21)
draw.text((18,12),'SGODOT-402 / 原生图标与名字条 · 接入核对',font=heading,fill='#4C4A3E')
for x,name,text in [(0,'native_icon_name_bar','现状 0.6 m：名字条遮住浮球上部'),
                    (752,'prompt_height_proposal_090m','临时提案 0.9 m：未提交运行时，待评估')]:
    image=Image.open(OUT/'captures'/(name+'.png')).convert('RGB');assert image.size==(360,800)
    board.paste(image.resize((720,1600),Image.Resampling.NEAREST),(x,105))
    draw.text((x+18,62),text,font=label,fill='#4C4A3E')
draw.text((18,1712),'各侧原生 360×800，2 倍显示 / 同机位 43° / 同一原生 Fish Trap · 0/3 名字条',font=small,fill='#4C4A3E')
draw.text((1320,1712),'【黄忠】',font=small,fill='#4C4A3E')
path=DOC/(prefix+'native_prompt_comparison.jpg');board.save(path,quality=95,subsampling=0,optimize=True);files.append(path)
manifest=json.loads((ROOT/'assets/props/fish_trap_marker/manifest.json').read_text())
references={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((SRC/'reference').iterdir()) if p.is_file()}
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
    'concept':'402 b82ebef9; approved A / 0331ee23','manifest':manifest,'reference_sha256':references,**reports,
    'integration_note':'Existing .6m prompt overlap is retained as evidence; .9m image is a temporary review proposal only.'}
path=DOC/(prefix+'validation.json');path.write_text(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False)+'\n');files.append(path)
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,
    'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'author':'黄忠',
    'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in files],ensure_ascii=False,indent=2)+'\n')
print(DOC)
