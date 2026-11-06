"""Label unmodified Godot pixels, retain reports and hash deliverable images."""
from pathlib import Path
import hashlib,json,re,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
QA=ROOT/'output/alcatraz-trees-cd-424';OUT=ROOT/'docs/design/alcatraz-trees-cd-424-2026-11-06'
OUT.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def text(im,xy,label,size=22,center=False):
    draw=ImageDraw.Draw(im);font=ImageFont.truetype(FONT,size)
    if center:xy=(xy[0]-draw.textlength(label,font=font)/2,xy[1])
    draw.text(xy,label,font=font,fill='#293E35')
def raw(name):return Image.open(QA/(name+'.png')).convert('RGB')
def vec(value):return [float(x) for x in re.findall(r'-?\d+(?:\.\d+)?',value)]
stats=json.loads((HERE/'asset_stats.json').read_text())
render=json.loads((QA/'render-validation.json').read_text())
lod=json.loads((QA/'lod-validation.json').read_text())
geometry=json.loads((QA/'geometry-validation.json').read_text())
assert render['passed'] and lod['passed'] and geometry['passed']
for name,e in stats['assets'].items():assert render['assets'][name]['sha256']==e['sha256']

sheet=Image.new('RGB',(1500,1070),'#F3F0E7')
text(sheet,(24,12),'SGODOT-424  四种树 / 原尺寸 + 1.75 m 游戏角色',30)
text(sheet,(24,56),'a 风吹柏树 · b 圆冠树 · c 高窄意大利柏 · d 低伞冠小橄榄树    |    Godot Mobile / 岛内日光',21)
sheet.paste(raw('four_trees_avatar'),(0,92))
labels={'alc_tree_a':['a / 已有风吹树','6.42 m · 520 面'],
        'alc_tree_b':['b / 已有圆冠树','6.28 m · 316 面'],
        'alc_tree_c':['c / 高窄意大利柏','7.80 m · 240 / 116 面'],
        'alc_tree_d':['d / 低伞冠小橄榄树','3.60 m · 316 / 118 面']}
for row in render['gallery']:
    x,y=vec(row['label_at'])
    for i,line in enumerate(labels[row['asset']]):text(sheet,(x,y+108+i*28),line,20 if i else 23,True)
x,y=vec(render['avatar_label_at']);text(sheet,(x,y+108),'游戏角色',21,True);text(sheet,(x,y+138),'1.75 m',19,True)
text(sheet,(24,1044),'【赵云】c / d 各一近档、一远档；每个文件 1 mesh / 1 surface，原点在树根底部中心。',18)
sheet.save(OUT/'SGODOT-424_TREES_CD_v1_lineup.png')

sheet=Image.new('RGB',(1440,1170),'#F3F0E7')
text(sheet,(24,12),'SGODOT-424  山坡同机位替换对照',30)
text(sheet,(24,56),'43° / yaw 35° / 视宽 27 m 的山坡审阅机位；各 720 × 1000 原像素，非默认开场镜头。',21)
text(sheet,(24,91),'替换前：26 棵 a / b',22);text(sheet,(744,91),'替换后：8 a + 6 b + 4 c + 8 d',22)
sheet.paste(raw('slope_before'),(0,126));sheet.paste(raw('slope_after'),(720,126))
text(sheet,(24,1140),'【赵云】12 株原位替换，树根坐标 / 朝向 / 碰撞保持；正式整岛由马可波罗接入。',18)
sheet.save(OUT/'SGODOT-424_TREES_CD_v1_slope_before_after.png')

sheet=Image.new('RGB',(1440,968),'#F3F0E7')
text(sheet,(24,12),'SGODOT-424  c / d 原生 40 m 切档',30)
text(sheet,(24,56),'43° / yaw 14.5° / 正交宽 6.72 m；距离量到共同 AABB 中心，每格原始 360 × 800。',21)
for i,(tree,distance) in enumerate([(t,d) for t in ['alc_tree_c','alc_tree_d'] for d in [39,41]]):
    key=tree+('_far' if distance==41 else '')
    text(sheet,(i*360+18,92),f'{tree[-1]} / {distance} m / {stats["assets"][key]["triangles"]} tris',23)
    sheet.paste(raw(f'{tree}_{distance}m'),(i*360,128))
text(sheet,(24,936),'【赵云】近远实例同时在场景里，由 Godot visibility_range 判断；另测 39.95 / 40.05 m 和侧背面。',19)
sheet.save(OUT/'SGODOT-424_TREES_CD_v1_39m_41m.png')

metrics={}
for tree in ['alc_tree_c','alc_tree_d']:
    for suffix in ['','_yaw60','_yaw150','_yaw240']:
        a=np.asarray(raw(tree+suffix+'_39m')).astype(float);b=np.asarray(raw(tree+suffix+'_41m')).astype(float)
        ma=np.abs(a-a[0,0]).max(axis=2)>10;mb=np.abs(b-b[0,0]).max(axis=2)>10;both=ma&mb
        def box(mask):
            y,x=np.where(mask);return [int(x.min()),int(y.min()),int(x.max()),int(y.max())]
        ba,bb=box(ma),box(mb)
        metrics[tree+suffix]={'silhouette_iou':round(float(both.sum()/(ma|mb).sum()),5),'near_bbox_px':ba,'far_bbox_px':bb,'max_bbox_edge_shift_px':max(abs(x-y) for x,y in zip(ba,bb)),'intersection_rgb_mae_255':round(float(np.abs(a[both]-b[both]).mean()),3)}
(OUT/'image-metrics.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2)+'\n')
for name in ['geometry-validation.json','render-validation.json','lod-validation.json','stage.json']:shutil.copy2(QA/name,OUT/name)
manifest=[]
for path in sorted(OUT.glob('SGODOT-*.png')):
    im=Image.open(path);assert max(im.size)<=1600
    manifest.append({'name':path.name,'path':path.relative_to(ROOT).as_posix(),'mime':'image/png','size':list(im.size),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(OUT/'media-manifest-v1.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(metrics,indent=2));print('PACKAGED',len(manifest),'images')
