"""Package verified native captures; no colour grading or model rescaling."""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];QA=ROOT/'output/coast-plants';RAW=QA/'v1.2';OUT=ROOT/'docs/design/coast-plants-435/v1.2';OUT.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def text(image,xy,value,size=19):ImageDraw.Draw(image).text(xy,value,font=ImageFont.truetype(FONT,size),fill='#2E3B36')
def raw(name):return Image.open(RAW/(name+'.png')).convert('RGB')
manifest=json.loads((ROOT/'assets/landmarks/_shared/coast_plants/manifest.json').read_text());assets=manifest['assets']
audit=json.loads((QA/'asset-validation.json').read_text());render=json.loads((RAW/'render-validation.json').read_text());lod=json.loads((RAW/'lod-validation.json').read_text())
assert audit['passed'] and render['passed'] and lod['passed']
for name,e in assets.items():
 assert e['sha256']==audit['assets'][name]['sha256']==render['assets'][name]['sha256']
for group in manifest['lod_groups']:
 assert lod['assets'][group['far']]['sha256']==assets[group['far']]['sha256']
 assert lod['assets'][group['far']]['near_sha256']==assets[group['near']]['sha256']
labels={'coast_grass_a':'海滨草 · 直立窄叶','coast_grass_b':'海滨草 · 低矮散开','coast_iceplant_a':'冰花 · 小厚垫','coast_iceplant_b':'冰花 · 大厚垫','coast_shrub_a':'矮灌木 · 灰绿扁冠','coast_shrub_b':'矮灌木 · 黄绿圆冠','coast_cypress':'四层风斜柏树 · 近档','coast_cypress_far':'四层风斜柏树 · 远档','coast_palm':'下垂长叶棕榈 · 近档','coast_palm_far':'下垂长叶棕榈 · 远档'}
sheet=Image.new('RGB',(1400,1510),'#F3F0E7')
text(sheet,(20,10),'SGODOT-435  通用海岸植被 v1.2 / 10 件 · 单 surface · 哑光顶点色',28)
text(sheet,(20,51),'小件与树分区取景；每格均有 1.75 m 游戏人物。近 / 远档同尺度、同原点，40 m 切换。',19)
for i,(name,e) in enumerate(assets.items()):
 image=raw('part_'+name)
 if i<6:
  x=10+(i%3)*463;y=84+(i//3)*380
  assert image.size==(450,330);sheet.paste(image,(x,y));ty=y+330
  text(sheet,(x+8,ty),labels[name]+' / '+str(e['triangles'])+' 面',18)
  text(sheet,(x+8,ty+26),name+' · 高 %.2f m'%e['height_m'],13)
 else:
  x=(i-6)*350;y=850
  assert image.size==(700,550);sheet.paste(image.resize((350,275),Image.Resampling.LANCZOS),(x,y));ty=y+275
  text(sheet,(x+8,ty),labels[name],17)
  text(sheet,(x+8,ty+26),str(e['triangles'])+' 面 · 高 %.2f m'%e['height_m'],14)
text(sheet,(20,1182),'冰花拼接：6 块大垫 / 间距 1.18 × 0.84 m',18)
text(sheet,(720,1182),'厚叶与粉紫小花近景',18)
sheet.paste(raw('iceplant_join'),(0,1210));sheet.paste(raw('iceplant_detail'),(700,1210))
total=sum(e['triangles'] for e in assets.values())
text(sheet,(20,1475),f'共 {total:,} 三角面；地被可用 MultiMesh 铺设；棕榈、柏树近远档 40 m 切换。',18)
text(sheet,(1250,1475),'【赵云】',18)
sheet.save(OUT/'SGODOT-435_COAST_PLANTS_v1.2_catalog.png')
image=raw('default_360x800');assert image.size==(360,800);text(image,(8,776),'【赵云】435 v1.2 · 426 / 430 / 432',11);image.save(OUT/'SGODOT-435_COAST_PLANTS_v1.2_default_360x800.png')
for name in ['asset-validation.json','render-validation.json','lod-validation.json','lod-image-metrics.json','reference-resources.json']:
 shutil.copy2((QA if name in ['asset-validation.json','reference-resources.json'] else RAW)/name,OUT/name)
media=[]
for path in sorted(OUT.glob('SGODOT-*.png')):
 size=Image.open(path).size;assert max(size)<=1600
 media.append({'name':path.name,'path':path.relative_to(ROOT).as_posix(),'mime':'image/png','size':list(size),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(OUT/'media-manifest-v1.2.json').write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print('Packaged',len(media),'verified captures')
