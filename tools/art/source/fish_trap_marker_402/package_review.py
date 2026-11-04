"""C64 enlargement: one signed native 43-degree capture with the approved 1.15m name bar."""
from pathlib import Path
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/trap-402-v11'
DOC=ROOT/'docs/design/fish-trap-marker-402-2026-11-04';DOC.mkdir(parents=True,exist_ok=True)
reports={k:json.loads((OUT/path).read_text()) for k,path in [
    ('geometry','geometry-validation.json'),('source','source-validation.json'),('godot','captures/godot-validation.json')]}
assert all(r['passed'] for r in reports.values())
assert 'ERROR:' not in (OUT/'render.log').read_text() and 'NaN' not in (OUT/'render.log').read_text()
font='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
prefix='SGODOT-402_fish_trap_marker_v1.1_';files=[]
image=Image.open(OUT/'captures/bank_43deg_prompt_115m.png').convert('RGB');assert image.size==(360,800)
board=Image.new('RGB',(760,1860),'#F7F5EF');draw=ImageDraw.Draw(board)
def text(x,y,label,size=22):draw.text((x,y),label,font=ImageFont.truetype(font,size),fill='#4C4A3E')
text(20,12,'SGODOT-402 / v1.1 / C64 鱼笼放大 1.35 倍',28)
text(20,57,'43° 塘边实拍 · 名字条 1.15 m · 右侧为原生抛竿浮漂',22)
board.paste(image.resize((720,1600),Image.Resampling.NEAREST),(20,105))
text(20,1718,'宽 0.6075 m / 水上 0.513 m / 水下 0.0675 m',23)
text(20,1752,'500 面 / 1 surface · 顶点烘大，单位比例 · 样式及颜色不变',21)
gap=reports['godot']['prompt']['gap_px']
text(20,1784,f'原生 360×800，2 倍展示 · 名字条离浮球约 {gap:.1f} 逻辑像素',21)
text(20,1814,'【黄忠】Godot Mobile / Vulkan / RTX 2060 · 隔离 b1 实渲',20)
path=DOC/(prefix+'bank_43deg_prompt_115m.png');board.save(path);files.append(path)
manifest=json.loads((ROOT/'assets/props/fish_trap_marker/manifest.json').read_text())
references={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((SRC/'reference').iterdir()) if p.is_file()}
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
    'concept':'402 b82ebef9 / 0331ee23; C64 enlargement / 67b2649f','manifest':manifest,'reference_sha256':references,**reports,
    'integration_note':'Approved 1.15m trap prompt offset is applied only to the private b1 review copy. Integrator changes p0_pond.gd:606 from .6 to 1.15m and removes the old trap root 1.6 scale.'}
path=DOC/(prefix+'validation.json');path.write_text(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False)+'\n');files.append(path)
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,
    'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'author':'黄忠',
    'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in files],ensure_ascii=False,indent=2)+'\n')
print(DOC)
