"""Package actual Godot frames, measurements and readback-ready review media."""
import csv
import hashlib
import json
from pathlib import Path
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/sprinkler-244'
DOC=ROOT/'docs/design/sprinkler-244-2026-10-30'
SOURCE=ROOT/'tools/art/source/sprinkler_244'
REVISION='--proportion-revision' in sys.argv
entry=json.loads((ROOT/'assets/farm/art/manifest.json').read_text())['assets']['sprinkler']
VERSION=entry.get('art_revision','v1')
PREFIX='SGODOT-244_SPRINKLER_'+VERSION.replace('.','_')+'_'
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
DOC.mkdir(parents=True,exist_ok=True)
geometry=json.loads((OUT/'geometry-validation.json').read_text())
runtime=json.loads((OUT/'captures/godot-validation.json').read_text())
source=json.loads((OUT/'source-validation.json').read_text())
rebuild=json.loads((OUT/'reproducibility.json').read_text())
assert geometry['passed'] and runtime['passed'] and source['passed'] and rebuild['byte_identical']
assert runtime['asset_sha256']==entry['sha256'] and runtime['art_revision']==VERSION
measure=geometry['measurements']


def font(size): return ImageFont.truetype(FONT,size)


def text(draw,xy,label,size=24,colour='#263d42'):
    draw.text(xy,label,font=font(size),fill=colour)


def raw(name): return Image.open(OUT/('captures/'+name+'.png')).convert('RGB')


def save(image,name): image.save(DOC/(PREFIX+name+'.png'))


def portrait(name,title,note):
    image=raw(name)
    draw=ImageDraw.Draw(image)
    factor=image.width//360
    draw.rectangle((0,0,image.width,73*factor),fill='#f5f7f3')
    text(draw,(12*factor,10*factor),'SGODOT-244 / 洒水器 '+VERSION,16*factor)
    text(draw,(12*factor,39*factor),title,13*factor)
    draw.rectangle((0,image.height-68*factor,image.width,image.height),fill='#f5f7f3')
    text(draw,(12*factor,image.height-57*factor),'黄忠 · %d tris · %.3f m · 人物 1.745 m'%
         (entry['triangles'],measure['size_xyz_m'][1]),12*factor)
    text(draw,(12*factor,image.height-32*factor),note,11*factor)
    save(image,name)


portrait('default_43deg_360','默认 43° / 14.5° · 正交宽 6.72 m','真实 plot.glb / 8 株中期作物 / Godot Mobile')
if not REVISION:
    portrait('default_43deg_hd','默认 43° / 14.5° · 同构图高清渲染','真实 plot.glb / 8 株中期作物 / Godot Mobile')
portrait('minimum_zoom_360','最远缩放 0.8 · 正交宽 8.40 m','完整 360 × 800 游戏取景；未放大模型')

top=Image.new('RGB',(1000,1200),'#f5f7f3'); top.paste(raw('top'),(0,100)); draw=ImageDraw.Draw(top)
text(draw,(28,17),'SGODOT-244 / 正俯视投影 / '+VERSION,29)
text(draw,(28,57),'黄忠 · 真实田块 0.94 m · 中心距 1.30 m',22)
half=.47/4.2*1000
draw.rectangle((500-half,600-half,500+half,600+half),outline='#31777c',width=3)
draw.line((500-half,750,500+half,750),fill='#31777c',width=3)
for x in [500-half,500+half]:draw.line((x,740,x,760),fill='#31777c',width=3)
text(draw,(437,765),'0.940 m',23)
text(draw,(28,1115),'喷头旋转外径 %.5f m；距本田外边至少 %.5f m'%
     (measure['head_swept_diameter_m'],measure['plot_min_edge_clearance_m']),24)
text(draw,(28,1157),'框线为真实 plot.glb 的 XZ 包围盒；没有伸入走道或邻田。',21)
save(top,'top')

if VERSION=='v1.2':
    ids={c['id'] for c in runtime['captures']}
    for mode,title,width in [('default','43° 默认镜头',6.72),('minimum','43° 最远缩放 0.8',8.40)]:
        comparison=Image.new('RGB',(744,936),'#f5f7f3'); draw=ImageDraw.Draw(comparison)
        text(draw,(16,10),'SGODOT-244 / v1.1 与 v1.2 / '+title,23)
        for i,(revision,label) in enumerate([
            ('v1_1','v1.1 / 778 tris / H 0.647 m'),
            ('v1_2','v1.2 / %d tris / H %.3f m'%(entry['triangles'],measure['size_xyz_m'][1]))]):
            capture_id='comparison_'+mode+'_'+revision
            assert capture_id in ids
            frame=raw(capture_id)
            assert frame.size==(360,800)
            x=12+i*372
            comparison.paste(frame,(x,70))
            text(draw,(x+6,45),label,16)
        text(draw,(16,881),'黄忠 · 每侧原生 360 × 800 · 视宽 %.2f m · 人物 1.745 m'%width,19)
        text(draw,(16,910),'同光同机位同摆放；未裁切、未分别放大模型或画面。',18)
        save(comparison,'comparison_'+mode+'_360')

if not REVISION:
    rotation=Image.new('RGB',(1800,735),'#f5f7f3'); draw=ImageDraw.Draw(rotation)
    text(draw,(30,16),'SGODOT-244 / 喷头旋转轴心检查 · 黄忠',29)
    for i,angle in enumerate([0,45,90]):
        rotation.paste(raw('head_%03d'%angle),(i*600,65))
        text(draw,(i*600+25,675),'head Y = %d° / 轴心 (0, %.2f, 0)'%(angle,entry['head_pivot'][1]),23)
    text(draw,(30,711),'同一真实田块、材质、光照和镜头；仅 head 旋转，base 与 spray_origin 固定。',17)
    save(rotation,'head_rotation')

    colour=raw('brass_wood'); draw=ImageDraw.Draw(colour)
    draw.rectangle((0,0,1000,108),fill='#f5f7f3')
    text(draw,(25,12),'SGODOT-244 / 黄铜与实际农场颜色 · 黄忠',29)
    text(draw,(25,58),'同一 FarmArt.material() 和农场光照；上方为真实 plot.glb',22)
    for x,title,code in [(99,'黄铜喷头','E8CE5B'),(382,'农场木色 / storage.glb','CBA067'),(663,'真实田沿土色 / plot.glb','96764F')]:
        text(draw,(x,842),title,20)
        text(draw,(x,875),'源色 #'+code,20)
    draw.rectangle((0,925,1000,1000),fill='#f5f7f3')
    text(draw,(25,939),'实物更正：plot.glb 是土畦，没有木框；另取现有木件作木色参照。',22)
    text(draw,(25,972),'黄铜 H=48.94° / 木色 H=34.20°；色相差 14.74°，避免偏橙混色。',20)
    save(colour,'colour_comparison')

# These full-resolution controls isolate the real rear crop and the occluder.
without=np.array(raw('rear_crop_without_sprinkler_mask'))
with_model=np.array(raw('rear_crop_with_sprinkler_mask'))
visible=np.min(without,axis=2)>200
occluded=visible & (np.max(with_model,axis=2)<50)
assert visible.sum()>200
fraction=float(occluded.sum()/visible.sum())
assert fraction<.5
pixel={'check':'sprinkler occludes less than half the actual rear mid-stage crop at default camera',
       'passed':True,'baseline_crop_pixels':int(visible.sum()),'occluded_pixels':int(occluded.sum()),
       'occluded_fraction':fraction,'crop':'L / stage 1 at x=0,z=-1.30 m',
       'method':'Same camera/mesh, white crop against black; compare with/without black sprinkler, no shadows.'}
validation={'author':'黄忠','task':'SGODOT-244','art_revision':VERSION,'geometry':geometry,'godot':runtime,'source':source,
            'reproducibility':rebuild,'occlusion':pixel,
            'evidence':json.loads((OUT/'source-evidence.json').read_text()),
            'reference':{'spec':'SGODOT-244_sprinkler-spec-v1.1.md','sheet':'SGODOT-244_sprinkler-sheet-v1.png',
                         'amendment':'tools/art/source/sprinkler_244/revision-'+VERSION+'.md',
                         'dimension_authority':'specification, not measured from image'},
            'scope':'Offline desktop art verification; tech and visual review pending, no gameplay integration or phone performance claim.'}
(DOC/(PREFIX+'validation.json')).write_text(json.dumps(validation,indent=2,ensure_ascii=False)+'\n')
rows=[['总三角形',entry['triangles'],'<= 800'],['base 三角形',entry['parts']['base']['triangles'],'1 surface'],['head 三角形',entry['parts']['head']['triangles'],'1 surface'],
      ['总高 / 床面以上 m',measure['size_xyz_m'][1],'约 0.52 (v1.2)'],['宽 X m',measure['size_xyz_m'][0],'实际顶点'],
      ['深 Z m',measure['size_xyz_m'][2],'实际顶点'],['喷头旋转外径 m',measure['head_swept_diameter_m'],'<= 0.40'],
      ['石垫直径 m',measure['stone_diameter_m'],'0.24-0.26 (v1.1)'],['喷臂截面直径 m',measure['arm_section_diameter_m'],'0.04 (v1.1)'],
      ['蓝色顶帽直径 m',measure['cap_diameter_m'],'0.10'],['喷头轴心 / spray_origin',str(entry['head_pivot']),'本地米制'],
      ['角色高 m',1.745,'按实际姿态顶点等比校准'],['后方作物遮挡比例',fraction,'< 0.5']]
if REVISION:
    measurements=source['measurements']
    hub=measurements['Rounded yellow brass rotating hub']
    rows += [['立杆下段直径 m',measurements['riser_at_0.05m']['diameter_m'],'0.13'],
             ['立杆上段直径 m',measurements['riser_at_0.362m']['diameter_m'],'0.11'],
             ['轮毂直径 m',hub['diameter_m'],'0.13-0.14'],
             ['轮毂高度 m',hub['top_m']-hub['bottom_m'],'约 0.07'],
             ['喷嘴直径 m',measurements['Left nozzle']['diameter_m'],'约 0.05'],
             ['蓝帽高度 m',measure['cap_height_m'],'圆鼓加高'],
             ['蓝帽上腹直径 m',measure['cap_upper_belly_diameter_m'],'y=0.489 m 处 Ø0.088']]
with (DOC/(PREFIX+'measurements.csv')).open('w',newline='') as f:
    writer=csv.writer(f,lineterminator='\n'); writer.writerow(['项目','实测值','要求/说明']);writer.writerows(rows)
table=['# SGODOT-244 实测尺寸','', '黄忠 · 2026-10-30。GLB 解码顶点和 Godot 实际导入结果。','',
       '| 项目 | 实测值 | 要求/说明 |','| --- | --- | --- |']
table += ['| '+' | '.join(str(x) for x in row)+' |' for row in rows]
table += ['', '实际 plot.glb 为圆角土畦，不含木框。黄铜对比图使用真实田沿土色，并另取 storage.glb 木色；未修改田块。','']
(DOC/(PREFIX+'measurements.md')).write_text('\n'.join(table))
for suffix in ['sprinkler.glb.import']:
    if not (ROOT/'assets/farm/art'/suffix).exists():
        shutil.copy2(OUT/'project/assets/farm/art'/suffix,ROOT/'assets/farm/art'/suffix)
uid=OUT/'project/tools/art/review_sprinkler.gd.uid'
if uid.exists():shutil.copy2(uid,ROOT/'tools/art/review_sprinkler.gd.uid')
incoming=Path.home()/'incoming/sprinkler-244'
for filename in ['SGODOT-244_sprinkler-spec-v1.1.md','SGODOT-244_sprinkler-sheet-v1.png']:
    if (incoming/filename).exists(): shutil.copy2(incoming/filename,SOURCE/filename)
    assert (SOURCE/filename).exists()
media=[]
for path in sorted(DOC.glob(PREFIX+'*')):
    if path.name.endswith('media-manifest.json'):continue
    row={'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size}
    if path.suffix=='.png':row['size']=list(Image.open(path).size)
    media.append(row)
(DOC/(PREFIX+'media-manifest.json')).write_text(json.dumps(media,indent=2)+'\n')
print('SPRINKLER_PACKAGED',len(media),'files; occlusion',fraction)
