"""Two signed v1.1 views with explicit before/after sRGB vertex-colour chips."""
from pathlib import Path
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/reed-clay-416'
DOC=ROOT/'docs/design/reed-clay-416-2026-11-04';PREFIX='SGODOT-416_reed_clay_v1.1_'
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
reports={k:json.loads((OUT/p).read_text()) for k,p in [('geometry','geometry-validation.json'),('source','source-validation.json'),
    ('colour','color-validation-v11.json'),('godot','captures-v11/godot-validation.json')]}
assert all(r['passed'] for r in reports.values())
assert 'ERROR:' not in (OUT/'render-v11.log').read_text()
def font(s):return ImageFont.truetype(FONT,s)
def text(d,xy,label,s=18):d.text(xy,label,font=font(s),fill='#473E32')
labels={'clay':'陶土主色 / 土砖','clay_light':'陶土亮部 / 土砖亮部','clay_shade':'坑底 / 陶土暗部','pit_wall':'坑内沿'}
changes=reports['colour']['changes'];files=[]
img=Image.open(OUT/'captures-v11/clay_F2_43deg.png').convert('RGB');assert img.size==(360,800)
board=Image.new('RGB',(790,955),'#F5F2EB');d=ImageDraw.Draw(board)
text(d,(20,10),'SGODOT-416 · 黏土坑 v1.1 · 只调整陶土顶点色',25)
text(d,(20,45),'F2 (7.6, −1.4) / 原生 360×800 / 默认 43° / 同一灯光',18)
board.paste(img,(20,80));text(d,(410,82),'顶点色 sRGB：v1 → v1.1',21)
for i,(role,c) in enumerate(changes.items()):
    y=127+i*94;text(d,(410,y),labels[role],18)
    for x,key in [(410,'before'),(595,'after')]:
        d.rounded_rectangle((x,y+29,x+37,y+57),radius=3,fill='#'+c[key])
        text(d,(x+44,y+30),'#'+c[key],18)
    text(d,(565,y+29),'→',19)
    text(d,(410,y+62),f"饱和度 −{c['saturation_reduction_percent']:.1f}% · V −{c['value_reduction_percent']:.1f}%",14)
text(d,(410,525),'同一 F2 实拍局部 · 4 倍展示',18)
crop=img.crop((224,455,300,514));board.paste(crop.resize((304,236),Image.Resampling.NEAREST),(425,560))
text(d,(410,820),'552 面 / 1 surface / 高 0.484 m',17)
gap=reports['godot']['clay_clearance']['switch_key']['mesh_gap_px']
text(d,(410,850),f'离切换键外圈 {gap:.2f} px',17)
text(d,(20,905),'【黄忠】木铲、草边、造型、尺寸、面数、.import 保持原样。',19)
text(d,(20,932),'Godot Mobile / Vulkan / RTX 2060 · 隔离 b1 实渲；色值为顶点色，不是截屏取色。',14)
path=DOC/(PREFIX+'clay_F2_43deg.png');board.save(path);files.append(path)
img=Image.open(OUT/'captures-v11/seven_resources_43deg.png').convert('RGB');assert img.size==(2800,850)
board=Image.new('RGB',(2800,1240),'#F5F2EB');d=ImageDraw.Draw(board)
text(d,(30,12),'SGODOT-416 · v1.1 黏土降饱和、压暗并偏红褐 · 七种采集物原尺寸并排',36)
text(d,(30,65),'同一塘灯光 / 43° · 芦苇 v1 已通过；本轮只改黏土、土砖、坑内沿顶点色。',27)
board.paste(img,(0,110))
for i,title in enumerate(['芦苇 · v1','黏土 · v1.1','树林','石堆','香草','亚麻','硬木']):
    x=1400+(i-3)*2.7*2800/20.3;d.text((x,960),title,font=font(28),fill='#473E32',anchor='mt')
for i,(role,c) in enumerate(changes.items()):
    x=35+i*695;text(d,(x,1010),labels[role]+' · sRGB 顶点色',25)
    for dx,key in [(0,'before'),(335,'after')]:
        d.rounded_rectangle((x+dx,1058,x+dx+65,1105),radius=4,fill='#'+c[key])
        text(d,(x+dx+80,1062),'#'+c[key],28)
    text(d,(x+280,1062),'→',28)
    text(d,(x,1120),f"S −{c['saturation_reduction_percent']:.1f}% / V −{c['value_reduction_percent']:.1f}%",24)
text(d,(30,1195),'【黄忠】Godot 4.7.2 / Mobile Vulkan / RTX 2060 · 原生模型、原尺寸；几何、木铲、草边与 .import 的保留检查通过。',26)
path=DOC/(PREFIX+'seven_resources_43deg.jpg');board.save(path,quality=95,subsampling=0,optimize=True);files.append(path)
payload={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
         'review_feedback':'416 1aa399b8: reed accepted; clay colour only',**reports}
path=DOC/(PREFIX+'validation.json');path.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n');files.append(path)
(DOC/'media-manifest-v11.json').write_text(json.dumps([{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
    'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'} for p in files],ensure_ascii=False,indent=2)+'\n')
print(DOC)
