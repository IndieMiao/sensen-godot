"""Label actual Godot captures without painting, retouching or cropping the scene."""
from pathlib import Path
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/flax-408'
DOC=ROOT/'docs/design/flax-408-2026-11-04';DOC.mkdir(parents=True,exist_ok=True)
PREFIX='SGODOT-408_flax_v1_'
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def font(size):return ImageFont.truetype(FONT,size)
def text(draw,xy,label,size=23):draw.text(xy,label,font=font(size),fill='#334638')
report=json.loads((OUT/'captures/godot-validation.json').read_text())
assert all(c['passed'] for c in report['checks'])
geometry=json.loads((OUT/'geometry-validation.json').read_text());assert geometry['passed']
image=Image.open(OUT/'captures/F2_default_43deg.png').convert('RGB')
assert image.size==(360,800)
sheet=Image.new('RGB',(760,1830),'#F5F4ED');d=ImageDraw.Draw(sheet)
text(d,(20,14),'SGODOT-408  亚麻田 v1 · F2 默认开场',28)
text(d,(20,58),'43° / 原出生点 / 360×800 实渲，等比 2 倍展示',22)
sheet.paste(image.resize((720,1600),Image.Resampling.NEAREST),(20,105))
text(d,(20,1720),'894 三角面 · 1 surface · 1.30 × 1.26 m · 高 0.687 m',22)
gap=report['slot']['switch_key']['mesh_gap_px']
text(d,(20,1753),f'F2 (7.9, −1.1) · 蓝花冠清楚 · 切换键轮廓间距 {gap:.1f} px',21)
text(d,(20,1790),'【黄忠】Godot Mobile / Vulkan · RTX 2060 · 隔离 b1 实渲',20)
sheet.save(DOC/(PREFIX+'F2_43deg.png'))
image=Image.open(OUT/'captures/resources_comparison_43deg.png').convert('RGB')
assert image.size==(1600,700)
sheet=Image.new('RGB',(1600,940),'#F5F4ED');d=ImageDraw.Draw(sheet)
text(d,(30,16),'SGODOT-408  亚麻田 v1 · 采集资源并排对比',31)
text(d,(30,62),'同一 43° 镜头、塘内灯光、单位比例；树林 / 芦苇 / 香草直接调用提供的旧代码。',24)
sheet.paste(image,(0,110))
for x,title,detail in [(278,'树林 · 旧件','树冠 / 高 2.122 m'),(626,'芦苇滩 · 旧件','棕顶香蒲 / 高 0.909 m'),
                       (974,'香草丛 · 旧件','圆绿叶簇 / 高 0.499 m'),(1322,'亚麻田 · 新件','淡蓝五瓣花 / 高 0.687 m')]:
    d.text((x,812),title,font=font(25),fill='#334638',anchor='mt')
    d.text((x,850),detail,font=font(21),fill='#334638',anchor='mt')
text(d,(30,901),'【黄忠】高度为地面以上实测最高点；原模型比例未调。亚麻：894 三角面 / 1 surface。',22)
sheet.save(DOC/(PREFIX+'resource_comparison.png'))
payload={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
         'geometry':geometry,'godot':report,'scope':'Private desktop Godot art verification; no runtime integration or phone test'}
(DOC/'validation.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n')
media=[]
for path in sorted(DOC.glob(PREFIX+'*.png')):
    media.append({'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                  'pixels':list(Image.open(path).size),'author':'黄忠',
                  'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'})
media.append({'file':'validation.json','sha256':hashlib.sha256((DOC/'validation.json').read_bytes()).hexdigest(),
              'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'})
(DOC/'media-manifest.json').write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print(DOC)
