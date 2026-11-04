"""Sign the three actual Godot views; keep the two gameplay captures at 360x800."""
from pathlib import Path
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/reed-clay-416'
DOC=ROOT/'docs/design/reed-clay-416-2026-11-04';DOC.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';PREFIX='SGODOT-416_reed_clay_v1_'
reports={k:json.loads((OUT/path).read_text()) for k,path in [('geometry','geometry-validation.json'),
    ('source','source-validation.json'),('godot','captures/godot-validation.json')]}
assert all(r['passed'] for r in reports.values())
assert 'ERROR:' not in (OUT/'render.log').read_text()
gap=reports['godot']['clay_clearance']['switch_key']['mesh_gap_px']
def font(size):return ImageFont.truetype(FONT,size)
def text(d,xy,label,size=16):d.text(xy,label,font=font(size),fill='#36462F')
files=[]
for key,title,subtitle,lines in [
    ('reed_L1_43deg','SGODOT-416 · 芦苇滩 A','Fern Pond / L1 / 默认 43° / 360×800',
     ['890 面 · 1 surface · 高 0.990 m','原场景树冠遮住部分叶丛；完整造型见并排图','L1 (-0.3, −6.6) · 人物 stand (0.88, −6.62)']),
    ('clay_F2_43deg','SGODOT-416 · 黏土坑 A','Willow Pond / F2 开场 / 默认 43° / 360×800',
     ['552 面 · 1 surface · 含木铲高 0.484 m',f'离切换键外圈最近 {gap:.2f} px（要求 ≥ 12 px）','F2 (7.6, −1.4) · 原出生点、原开场镜头'])]:
    img=Image.open(OUT/'captures'/(key+'.png')).convert('RGB');assert img.size==(360,800)
    board=Image.new('RGB',(400,985),'#F5F4ED');d=ImageDraw.Draw(board)
    text(d,(20,10),title,22);text(d,(20,43),subtitle,14);board.paste(img,(20,70))
    for i,line in enumerate(lines):text(d,(20,880+i*24),line,14)
    text(d,(20,958),'【黄忠】Godot Mobile / Vulkan · RTX 2060',14)
    path=DOC/(PREFIX+key+'.png');board.save(path);files.append(path)
img=Image.open(OUT/'captures/seven_resources_43deg.png').convert('RGB');assert img.size==(2800,850)
board=Image.new('RGB',(2800,1080),'#F5F4ED');d=ImageDraw.Draw(board)
text(d,(30,12),'SGODOT-416 · 七种采集资源并排 / 同一塘灯光 / 原尺寸 / 43°',37)
text(d,(30,65),'芦苇靠棕色香蒲头与暖黄绿尖叶辨认；黏土为浅坑、赭色土堆、细木铲，仅两小块土砖。',27)
board.paste(img,(0,110))
for i,(title,detail) in enumerate([('芦苇滩 · 新件','890 面 / 1 surface'),('黏土坑 · 新件','552 面 / 1 surface'),
    ('树林 · 旧件','原旧代码 / 原比例'),('石堆 · 旧件','原旧代码 / 原比例'),('香草 · 旧件','原旧代码 / 原比例'),
    ('亚麻 · 408','c0179102 / 原尺寸'),('硬木 · 408','aee148bf / 原尺寸')]):
    x=1400+(i-3)*2.7*2800/20.3
    d.text((x,960),title,font=font(27),fill='#36462F',anchor='mt')
    d.text((x,1000),detail,font=font(22),fill='#36462F',anchor='mt')
text(d,(30,1040),'【黄忠】隔离 b1 67116c6d / Godot 4.7.2 Mobile Vulkan / 原游戏地面、灯光与材质；模型未作比较用缩放。',24)
path=DOC/(PREFIX+'seven_resources_43deg.jpg');board.save(path,quality=95,subsampling=0,optimize=True);files.append(path)
payload={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
         'design':'SGODOT-416 A/A approved in e061cf13',
         'reference_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (SRC/'reference').iterdir() if p.is_file()},
         'reed_scene_note':'Original fixed foreground tree partly occludes the lower reed clump at L1. Requested slot, stand and native recentered 43-degree view are retained; comparison shows full model.',**reports}
path=DOC/(PREFIX+'validation.json');path.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n');files.append(path)
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
    'bytes':p.stat().st_size,'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in files],ensure_ascii=False,indent=2)+'\n')
print(DOC)
