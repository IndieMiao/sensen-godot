"""Package verified native captures; no colour grading or model rescaling."""
from pathlib import Path
import hashlib,json,shutil
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[4];QA=ROOT/'output/coast-plants';OUT=ROOT/'docs/design/coast-plants-435';OUT.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def text(image,xy,value,size=19):ImageDraw.Draw(image).text(xy,value,font=ImageFont.truetype(FONT,size),fill='#2E3B36')
def raw(name):return Image.open(QA/(name+'.png')).convert('RGB')
manifest=json.loads((ROOT/'assets/landmarks/_shared/coast_plants/manifest.json').read_text());assets=manifest['assets']
audit=json.loads((QA/'asset-validation.json').read_text());render=json.loads((QA/'render-validation.json').read_text());lod=json.loads((QA/'lod-validation.json').read_text())
assert audit['passed'] and render['passed'] and lod['passed']
for name,e in assets.items():
 assert e['sha256']==audit['assets'][name]['sha256']==render['assets'][name]['sha256']
for group in manifest['lod_groups']:
 assert lod['assets'][group['far']]['sha256']==assets[group['far']]['sha256']
 assert lod['assets'][group['far']]['near_sha256']==assets[group['near']]['sha256']
labels={'coast_grass_a':'海滨草 · 直立窄叶','coast_grass_b':'海滨草 · 低矮散开','coast_iceplant_a':'冰花 · 紧凑地被','coast_iceplant_b':'冰花 · 横向地被','coast_shrub_a':'矮灌木 · 灰绿扁冠','coast_shrub_b':'矮灌木 · 黄绿圆冠','coast_cypress':'风斜蒙特雷柏 · 近档','coast_cypress_far':'风斜蒙特雷柏 · 远档','coast_palm':'海岸扇叶棕榈 · 近档','coast_palm_far':'海岸扇叶棕榈 · 远档'}
sheet=Image.new('RGB',(1400,1220),'#F3F0E7')
text(sheet,(20,10),'SGODOT-435  通用海岸植被 v1 / 10 件 · 单 surface · 哑光顶点色',28)
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
text(sheet,(20,1182),'共 2,402 三角面；地被 / 草丛 / 灌木可按种类组成 MultiMesh 批次。',19)
text(sheet,(1250,1182),'【赵云】',18)
sheet.save(OUT/'SGODOT-435_COAST_PLANTS_v1_catalog.png')
image=raw('default_360x800');assert image.size==(360,800);text(image,(8,776),'【赵云】435 v1 · 426 / 430 / 432',11);image.save(OUT/'SGODOT-435_COAST_PLANTS_v1_default_360x800.png')
image=raw('coast_overview_warm');text(image,(20,15),'SGODOT-435 / 12 m 海岸带 / 暖沙岸石 + 430 浪花 + 432 海湾',24);text(image,(1240,807),'【赵云】',18);image.save(OUT/'SGODOT-435_COAST_PLANTS_v1_overview_warm.png')
lodsheet=Image.new('RGB',(1440,900),'#F3F0E7');text(lodsheet,(20,8),'43° / 6.72 m · Godot visibility_range 自动切档 / 40 m',25)
for i,name in enumerate(['coast_cypress_39m','coast_cypress_41m','coast_palm_39m','coast_palm_41m']):
 image=raw(name);assert image.size==(360,800);lodsheet.paste(image,(i*360,80))
 label=['柏树 39 m · 372 面','柏树 41 m · 118 面','棕榈 39 m · 316 面','棕榈 41 m · 120 面'][i];text(lodsheet,(i*360+10,48),label,19)
text(lodsheet,(1260,869),'【赵云】',18);lodsheet.save(OUT/'SGODOT-435_COAST_PLANTS_v1_lod_39_41.png')
for name in ['asset-validation.json','render-validation.json','lod-validation.json','lod-image-metrics.json','reference-resources.json']:shutil.copy2(QA/name,OUT/name)
media=[]
for path in sorted(OUT.glob('SGODOT-*.png')):
 size=Image.open(path).size;assert max(size)<=1600
 media.append({'name':path.name,'path':path.relative_to(ROOT).as_posix(),'mime':'image/png','size':list(size),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(OUT/'media-manifest-v1.json').write_text(json.dumps(media,ensure_ascii=False,indent=2)+'\n')
print('Packaged',len(media),'verified captures')
