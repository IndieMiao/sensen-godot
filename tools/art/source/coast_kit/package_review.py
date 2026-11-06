"""Package existing native captures. Deliberately contains no example layout."""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image,ImageDraw,ImageFont
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/coast-kit';OUT=ROOT/'docs/design/coast-kit-2026-11-06'
OUT.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def text(im,xy,s,size=21):ImageDraw.Draw(im).text(xy,s,font=ImageFont.truetype(FONT,size),fill='#2E3B36')
def raw(name):return Image.open(QA/(name+'.png')).convert('RGB')
assets=json.loads((HERE/'asset_stats.json').read_text())['assets']
verification=json.loads((QA/'asset-validation.json').read_text())
render=json.loads((QA/'render-validation.json').read_text())
assert verification['passed'] and render['passed']
for name,e in assets.items():assert e['sha256']==render['assets'][name]['sha256']
labels=['岸石直段 · 低','岸石直段 · 高','岸石外角 · 低','岸石外角 · 高','岸石内角 · 低','岸石内角 · 高','散石 a','散石 b','散石 c','混凝土护岸墙','木码头直段','木码头尽头','木码头 + 系缆桩','小浮标','下水台阶']
sheet=Image.new('RGB',(1500,1160),'#F3F0E7')
text(sheet,(24,10),'SGODOT-426  海岸套件 / 15 件 · 2 m 模数',30)
text(sheet,(24,52),'每格同一 1.75 m 游戏角色、相同镜头比例与灯光；每件单 surface、哑光顶点色、无贴图。',21)
for i,(name,e) in enumerate(assets.items()):
    x=(i%5)*300;y=84+(i//5)*350
    sheet.paste(raw('part_'+name),(x,y))
    text(sheet,(x+10,y+301),labels[i]+' / '+str(e['triangles'])+' 面',18)
    text(sheet,(x+10,y+327),name,12)
text(sheet,(24,1138),'【赵云】全部 15 件共 2,348 面；岸石两种高度共享端口，码头甲板 2 × 2 m。',17)
sheet.save(OUT/'SGODOT-426_COAST_v1_catalog.png')

image=raw('example_default_360x800');assert image.size==(360,800)
text(image,(10,776),'【赵云】SGODOT-426',12)
image.save(OUT/'SGODOT-426_COAST_v1_default_360x800.png')

sheet=Image.new('RGB',(1400,1120),'#F3F0E7')
text(sheet,(24,12),'SGODOT-426  约 20 m 示例岸线 / 转角 · 码头 · 台阶',28)
text(sheet,(24,52),'43° 全景审阅机位，视宽 17.5 m；2 m 格计 20 m，含两个出入口的实际边线约 19.14 m。',20)
sheet.paste(raw('example_whole_shore'),(0,80))
text(sheet,(24,1092),'【赵云】示例仅用于审阅出图；不交 layout、不进入游戏。水面与地表是本次隔离审阅背景。',18)
sheet.save(OUT/'SGODOT-426_COAST_v1_shore_overview.png')

sheet=Image.new('RGB',(1200,900),'#F3F0E7')
text(sheet,(24,12),'SGODOT-426  岸石拼接近景',28)
sheet.paste(raw('example_corner_seam'),(0,60))
text(sheet,(24,872),'【赵云】低直段 → 外转角 → 高直段；端口截面一致。所有 43 组 out→in 配对通过几何核对。',17)
sheet.save(OUT/'SGODOT-426_COAST_v1_seams.png')

for file in ['asset-validation.json','render-validation.json']:shutil.copy2(QA/file,OUT/file)
media=[]
for path in sorted(OUT.glob('SGODOT-*.png')):
    size=Image.open(path).size;assert max(size)<=1600
    media.append({'name':path.name,'path':path.relative_to(ROOT).as_posix(),'mime':'image/png','size':list(size),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(OUT/'media-manifest-v1.json').write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print('Packaged',len(media),'review images, <=1600 px. No layout delivered.')
