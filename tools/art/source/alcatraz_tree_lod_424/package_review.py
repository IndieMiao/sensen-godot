"""Package unchanged native pixels and measured LOD comparison evidence."""
from pathlib import Path
import hashlib, json, shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
QA=ROOT/'output/alcatraz-tree-lod-424'
OUT=ROOT/'docs/design/alcatraz-tree-lod-424-2026-11-06'
OUT.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
def font(size):return ImageFont.truetype(FONT,size)
def text(image,xy,label,size=22):ImageDraw.Draw(image).text(xy,label,font=font(size),fill='#303B3A')
def raw(name):return Image.open(QA/(name+'.png')).convert('RGB')
def bounds(mask):
    y,x=np.where(mask)
    return [int(x.min()),int(y.min()),int(x.max()),int(y.max())]
metrics={}
for tree in ['alc_tree_a','alc_tree_b']:
    for suffix in ['', '_yaw60', '_yaw150', '_yaw240']:
        name=tree+suffix
        a=np.asarray(raw(name+'_39m')).astype(float)
        b=np.asarray(raw(name+'_41m')).astype(float)
        ma=np.max(np.abs(a-a[0,0]),axis=2)>10
        mb=np.max(np.abs(b-b[0,0]),axis=2)>10
        both=ma&mb
        ba,bb=bounds(ma),bounds(mb)
        metrics[name]={
            'silhouette_iou':round(float(both.sum()/(ma|mb).sum()),5),
            'near_bbox_px':ba,'far_bbox_px':bb,
            'maximum_bbox_edge_shift_px':max(abs(x-y) for x,y in zip(ba,bb)),
            'mean_rgb_absolute_difference_on_intersection_255':round(float(np.abs(a[both]-b[both]).mean()),3),
            'note':'Foreground threshold 10/255 from constant background. Descriptive measurements, not an art-approval threshold.'}
(OUT/'image-metrics.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2)+'\n')
stats=json.loads((HERE/'asset_stats.json').read_text())
render=json.loads((QA/'render-validation.json').read_text())
assert render['passed']
for name,e in stats['assets'].items():assert render['assets'][name]['sha256']==e['sha256']

sheet=Image.new('RGB',(1440,968),'#F3F0E7')
text(sheet,(24,12),'SGODOT-424  恶魔岛树远档 / 39 m → 41 m',30)
text(sheet,(24,56),'Godot 4.7.2 Mobile · 43° / yaw 14.5° · 正交宽 6.72 m · 每格原始 360 × 800',20)
for i,(tree,distance) in enumerate([(t,d) for t in ['alc_tree_a','alc_tree_b'] for d in [39,41]]):
    n=stats['assets'][tree+'_far']['near_triangles' if distance==39 else 'triangles']
    text(sheet,(i*360+18,92),f'{tree[-1].upper()} / {distance} m / {n} tris',23)
    sheet.paste(raw(f'{tree}_{distance}m'),(i*360,128))
text(sheet,(24,936),'【赵云】引擎 visibility_range = 40 m，距离量到共同包围盒中心；原图未调色、未缩放。',19)
filename='SGODOT-424_TREE_LOD_v1_39m_41m.png'
sheet.save(OUT/filename)

# Native crops, 1 px remains 1 px, all three additional azimuths.
sheet=Image.new('RGB',(1600,1510),'#F3F0E7')
text(sheet,(20,12),'SGODOT-424  侧面 / 背面切档复核',29)
text(sheet,(20,54),'每组左 39 m 近档、右 41 m 远档；43° / 6.72 m；原图 400 × 600，仅裁去空背景。',20)
for row,yaw in enumerate([60,150,240]):
    y=94+row*460
    text(sheet,(20,y),f'yaw {yaw}°   A',21)
    text(sheet,(820,y),f'yaw {yaw}°   B',21)
    for col,(tree,distance) in enumerate([(t,d) for t in ['alc_tree_a','alc_tree_b'] for d in [39,41]]):
        sheet.paste(raw(f'{tree}_yaw{yaw}_{distance}m').crop((0,90,400,510)),(400*col,y+36))
text(sheet,(20,1480),'【赵云】相同相机 / 光照 / 材质；切换由 Godot 判断，不通过脚本手动隐藏模型。',19)
sheet.save(OUT/'SGODOT-424_TREE_LOD_v1_angles.png')

for name in ['geometry-validation.json','render-validation.json']:
    shutil.copy2(QA/name,OUT/name)
manifest=[]
for path in sorted(OUT.glob('SGODOT-*.png')):
    im=Image.open(path)
    assert max(im.size)<=1600
    manifest.append(dict(name=path.name,path=path.relative_to(ROOT).as_posix(),mime='image/png',size=list(im.size),sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
(OUT/'media-manifest-v1.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(metrics,ensure_ascii=False,indent=2))
print('Packaged',len(manifest),'review images; native pixels retained.')
