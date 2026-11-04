"""Three signed review plates from native 360x800 Godot captures."""
from pathlib import Path
import hashlib,json,math
from PIL import Image,ImageDraw,ImageFont
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/gathered-417'
DOC=ROOT/'docs/design/gathered-417-2026-11-04';DOC.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';PREFIX='SGODOT-417_gathered_v1_'
NAMES=['grove','rock_pile','reed_bank','clay_pit','herb_patch','hardwood_grove','flax_patch']
LABELS=['树林','石堆','芦苇滩','黏土坑','香草丛','硬木','亚麻']
stats=json.loads((SRC/'asset_stats.json').read_text());originals=json.loads((SRC/'original_metrics.json').read_text())
reports={k:json.loads((OUT/p).read_text()) for k,p in [('geometry','geometry-validation.json'),('source','source-validation.json'),('godot','captures/godot-validation.json')]}
assert all(r['passed'] for r in reports.values())
assert 'ERROR:' not in (OUT/'render.log').read_text()
for name in NAMES:
    assert reports['geometry']['assets'][name]['sha256']==stats[name]['sha256']
    assert max(abs(reports['godot']['assets'][name]['bounds'][j][i]-stats[name]['bounds'][j][i]) for j in range(2) for i in range(3))<1e-5,'Stale rendered model: '+name
def font(size):return ImageFont.truetype(FONT,size)
def text(draw,xy,label,size=20):draw.text(xy,label,font=font(size),fill='#35452F')
def raw(name):
    img=Image.open(OUT/'captures'/(name+'.png')).convert('RGB');assert img.size==(360,800);return img
files=[]
# Every pair is rendered simultaneously at native game scale; crop only empty staging grass.
board=Image.new('RGB',(1540,2320),'#F5F3EB');d=ImageDraw.Draw(board)
text(d,(24,14),'SGODOT-417 · 七种采集物：左原件 / 右采过',36)
text(d,(24,64),'同一塘灯光 / 43° / zoom 1 · 每格取原生 360×800 的 y=300–520 局部，2 倍展示',22)
for i,(name,label) in enumerate(zip(NAMES,LABELS)):
    x=20+(i%2)*760;y=115+(i//2)*540
    text(d,(x+12,y),f'{i+1:02}  {label} · {stats[name]["triangles"]} 面 / 1 surface',25)
    text(d,(x+12,y+37),f'最高点 {originals[name]["bounds"][1][1]:.3f} → {stats[name]["bounds"][1][1]:.3f} m',20)
    text(d,(x+145,y+68),'原件',20);text(d,(x+500,y+68),'采过',20)
    board.paste(raw('pair_'+name).crop((0,300,360,520)).resize((720,440),Image.Resampling.NEAREST),(x+10,y+98))
x=800;y=1745
text(d,(x,y),'七件均保持资源点原点',29)
text(d,(x,y+47),'每件 ≤600 面 / 1 surface / 无骨骼、动画、灯光',21)
text(d,(x,y+83),'平面包围盒均收在对应原件之内',22)
text(d,(x,y+122),'树林保留的小树高 0.950 m，原件最高 2.122 m',20)
text(d,(x,y+159),'扁石高 0.150 m；芦苇茬高 0.330 m',21)
text(d,(x,y+196),'统一新芽：四种植物各 2 棵，同形、同色、同尺度',20)
for j,(label,color) in enumerate([('树林浅桩','B18C5C'),('硬木胡桃桩','78472F'),('统一新芽','8FA46B'),('黏土薄层','9D674B')]):
    xx=x+(j%2)*310;yy=y+250+(j//2)*76
    d.rounded_rectangle((xx,yy,xx+45,yy+38),radius=4,fill='#'+color)
    text(d,(xx+57,yy),label,20);text(d,(xx+57,yy+27),'#'+color,17)
text(d,(24,2280),'【黄忠】Godot 4.7.2 / Mobile Vulkan / RTX 2060 · 原件与采过件均按单位比例实例化',23)
path=DOC/(PREFIX+'before_after.jpg');board.save(path,quality=95,subsampling=0,optimize=True);files.append(path)
# Native dimmed widget, whole viewport retained. The user asked for a cooldown example, not a live server change.
img=raw('pond_cooldown');board=Image.new('RGB',(760,1830),'#F5F3EB');d=ImageDraw.Draw(board)
text(d,(20,13),'SGODOT-417 · 采过后的冷却实拍',29)
text(d,(20,56),'原生 Dimmed 名字条 · Ready in 3h 12m · 360×800 原图 2 倍展示',19)
board.paste(img.resize((720,1600),Image.Resampling.NEAREST),(20,105))
text(d,(20,1720),'原件隐藏 / 采过件显示 · 同原点、同名字条锚点、同点击坐标与站位',19)
text(d,(20,1753),'冷却为离线审阅 fixture；使用原生 P0Ui / UiWorldNameBar，未提交程序接入。',17)
text(d,(20,1794),'【黄忠】43° / zoom 1 / Godot Mobile Vulkan / RTX 2060',20)
path=DOC/(PREFIX+'pond_cooldown.png');board.save(path);files.append(path)
# Seven full, unscaled phone views: visible patch width comes from actual source vertices, not a padded box.
board=Image.new('RGB',(1600,2040),'#F5F3EB');d=ImageDraw.Draw(board)
text(d,(20,13),'SGODOT-417 · 跟随镜头：上方可采 / 下方采过',32)
text(d,(20,60),'zoom 1 / 默认 43° / 每格完整 360×800，不缩放 · 量尺为土面或主扁石的真实顶点投影',21)
for i,(name,label) in enumerate(zip(NAMES,LABELS)):
    x=(i%4)*400;y=110+(i//4)*935;img=raw('follow_'+name)
    text(d,(x+20,y),label,24);board.paste(img,(x+20,y+45))
    metric=reports['godot']['pixel_widths'][name];r=metric['patch_screen_rect'];left=x+20+r[0];right=left+r[2];yy=y+45+r[1]+r[3]+6
    d.line((left,yy,right,yy),fill='#F5F3EB',width=3);d.line((left,yy,right,yy),fill='#344C36',width=1)
    for edge in [left,right]:d.line((edge,yy-3,edge,yy+3),fill='#344C36',width=1)
    text(d,(x+20,y+860),f'可见地块：{metric["patch_width_px"]:.1f} px ≥ 20 px',19)
    text(d,(x+20,y+891),'量土面 / 主扁石，不用树冠或新芽凑宽度',15)
x=1230;y=1080
text(d,(x,y),'可见地块宽度',26)
for i,(name,label) in enumerate(zip(NAMES,LABELS)):
    text(d,(x,y+55+i*45),f'{label}  {reports["godot"]["pixel_widths"][name]["patch_width_px"]:.1f} px',22)
for i,line in enumerate(['全部超过 20 px。','角色站 L1 原 stand (0.88, −6.62)。','同一帧：L2 可采、L1 采过。','镜头调用原生跟随 / recenter，','一屏宽 6.72 m，未拉近。','资源槽周围的装饰避让仅在','隔离工程模拟，交 410 接入。']):
    text(d,(x,y+420+i*34),line,18)
text(d,(20,2000),'【黄忠】尺寸 / UID / 原点 / 统一新芽 / 可见地块均有独立验证；正式运行时接入与 C67 验收另行处理。',21)
path=DOC/(PREFIX+'follow_visibility.jpg');board.save(path,quality=95,subsampling=0,optimize=True);files.append(path)
payload={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
    'concept':'417 e4c7afdd / interface 410 924d6611','original_metrics':originals,
    'uid_generation':json.loads((OUT/'uid-generation.json').read_text()),
    'scenery_review_only':json.loads((OUT/'scenery-mock.json').read_text()),**reports}
path=DOC/(PREFIX+'validation.json');path.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n');files.append(path)
(DOC/'media-manifest.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
    'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in files],ensure_ascii=False,indent=2)+'\n')
print(DOC)
