"""Package v1.2 native captures; no example scene or layout is delivered."""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image,ImageDraw,ImageFont
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/coast-kit';RAW=QA/'v1.2';OUT=ROOT/'docs/design/coast-kit-2026-11-06/v1.2'
OUT.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def text(im,xy,s,size=19):ImageDraw.Draw(im).text(xy,s,font=ImageFont.truetype(FONT,size),fill='#2E3B36')
def raw(name):return Image.open(RAW/(name+'.png')).convert('RGB')
assets=json.loads((HERE/'asset_stats.json').read_text())['assets']
verification=json.loads((QA/'asset-validation.json').read_text());render=json.loads((RAW/'render-validation.json').read_text());probe=json.loads((QA/'material-validation.json').read_text())
assert verification['passed'] and render['passed'] and probe['passed']
for name,e in assets.items():assert e['sha256']==render['assets'][name]['sha256']
names=['岸石直段·低','岸石直段·高','岸石外角·低','岸石外角·高','岸石内角·低','岸石内角·高','散石 a','散石 b','散石 c','护岸墙','码头直段','码头尽头','码头系缆桩','浮标','下水台阶']
labels=dict(zip(assets,names));sheet=Image.new('RGB',(1500,1530),'#F3F0E7')
text(sheet,(20,10),'SGODOT-426  海岸套件 v1.2 / 木板对齐 #830 · 双色板 · 湿带',28)
text(sheet,(20,50),'同一 GLB 只切 rock_palette；主件 43°、同一 1.75 m 人物。下方 25° 细节；湿带高 0.25 m。',19)
cell=0
for name,e in assets.items():
    rock=e['family'] in ['shore_rock','scatter']
    for style in (['sand','gray'] if rock else ['']):
        x=(cell%6)*250;y=82+(cell//6)*270
        image=raw('part_'+name+('_'+style if style else ''));assert image.size==(250,250)
        sheet.paste(image.crop((0,10,250,240)),(x,y))
        suffix=('暖沙' if style=='sand' else '冷灰褐') if style else str(e['triangles'])+' 面'
        text(sheet,(x+8,y+231),labels[name]+' / '+suffix,16)
        if rock:text(sheet,(x+8,y+251),str(e['triangles'])+' 面 · 同网格 / 单 surface',11)
        else:text(sheet,(x+8,y+251),name,11)
        cell+=1
assert cell==24
text(sheet,(20,1167),'护岸墙：出挑压顶 / 三道分块缝 / 底部渐淡湿带',20)
text(sheet,(770,1167),'码头：1.8 × 0.18 m 半块错缝 / 四角细桩',20)
sheet.paste(raw('detail_coast_seawall'),(0,1198));sheet.paste(raw('detail_coast_dock_bollard'),(750,1198))
# Detail images run to 1528; signature is already visible in the header/footer captions.
text(sheet,(1275,1485),'【赵云】',17)
sheet.save(OUT/'SGODOT-426_COAST_v1.2_catalog.png')
image=raw('example_default_360x800');assert image.size==(360,800)
text(image,(8,774),'【赵云】426 v1.2 · #824 浪花叠用',11)
image.save(OUT/'SGODOT-426_COAST_v1.2_default_360x800.png')
comparison=Image.new('RGB',(1400,650),'#F3F0E7')
text(comparison,(20,12),'#830 v1.1 参照 / #831 v1.2 码头木板统一',27)
text(comparison,(20,53),'左：刘备原材质近景；右：码头 43° 实渲。不同场景光照，图中未调色。',19)
reference=Image.open(QA/'wood-close-reference.png').convert('RGB').crop((0,0,1000,750))
comparison.paste(reference.resize((700,525),Image.Resampling.LANCZOS),(0,87))
comparison.paste(raw('wood_close'),(700,87))
text(comparison,(20,615),'1.8 × 0.18 m / 错开 0.9 m / 1.2 cm 缝 / 每块明暗 ±14%（线性）',18)
text(comparison,(1260,615),'【赵云】',18)
comparison.save(OUT/'SGODOT-426_COAST_v1.2_wood_match.png')
for source,target in [(QA/'asset-validation.json','asset-validation.json'),(RAW/'render-validation.json','render-validation.json'),(QA/'material-validation.json','material-validation.json'),(RAW/'foam-reference.json','foam-reference.json')]:shutil.copy2(source,OUT/target)
media=[]
for path in sorted(OUT.glob('SGODOT-*.png')):
    size=Image.open(path).size;assert max(size)<=1600
    media.append({'name':path.name,'path':path.relative_to(ROOT).as_posix(),'mime':'image/png','size':list(size),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(OUT/'media-manifest-v1.2.json').write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print('Packaged',len(media),'v1.2 images; both palettes use the same GLBs.')
