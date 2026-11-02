"""Exact raster regression for the protected inner contour, including the reported tip."""
from pathlib import Path
import json
import math
import sys
import hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4];OUT=ROOT/'output/mine-vein-355'
RUNTIME=ROOT/'output/monsters-355/runtime'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
pitch=math.radians(43);yaw=math.radians(14.5)
normal=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch)])
right=np.array([math.cos(yaw),0,-math.sin(yaw)]);up=np.cross(normal,right)
def raster(file,scale):
    doc,data=load_glb(file);primitive=doc['meshes'][0]['primitives'][0]
    points=np.array(accessor(doc,data,primitive['attributes']['POSITION']))
    indices=np.array(accessor(doc,data,primitive['indices'])).reshape(-1,3)
    pixels=np.column_stack(((points@right+6)*scale,(12-points@up)*scale))
    image=Image.new('L',(24*scale,20*scale));draw=ImageDraw.Draw(image)
    for triangle in indices:draw.polygon([tuple(pixels[i]) for i in triangle],fill=255)
    return np.array(image)>0
rows=[]
for scale in [40,100,160]:
    old=raster(RUNTIME/'assets/mine/backdrop/mine_backdrop.glb',scale)
    current=raster(RUNTIME/'assets/mine/types/vein/backdrop.glb',scale)
    added=current&~old
    rows.append({'pixels_per_m':scale,'added_pixels':int(added.sum()),'changed_pixels':int((old!=current).sum())})
    assert not added.any(),rows
old=Image.open(OUT/'outline/original.png').convert('RGB');current=Image.open(OUT/'outline/vein.png').convert('RGB')
a=np.array(old);b=np.array(current)
black=np.max(a,axis=2)==0
# fromarray can be readonly; floodfill needs a writable copy.
holes=Image.fromarray((black*255).astype(np.uint8)).copy();ImageDraw.floodfill(holes,(0,0),0)
inner=np.array(holes)>0
border=np.array(holes.filter(ImageFilter.MaxFilter(5)))>0
delta=np.max(np.abs(a.astype(np.int16)-b.astype(np.int16)),axis=2)
native={'protected_pixels':int(inner.sum()),'added_protected_pixels':int(((np.max(b,axis=2)>0)&inner).sum()),
    'inner_border_changed_pixels':int((delta[border]>0).sum()),'inner_border_max_delta':int(delta[border].max())}
assert 850000<native['protected_pixels']<950000,native
assert native['added_protected_pixels']==0 and native['inner_border_changed_pixels']==0,native
render=json.loads((OUT/'outline/render.json').read_text())
assert render['asset_sha256']['vein']==hashlib.sha256((RUNTIME/'assets/mine/types/vein/backdrop.glb').read_bytes()).hexdigest()
assert render['asset_sha256']['original']==hashlib.sha256((RUNTIME/'assets/mine/backdrop/mine_backdrop.glb').read_bytes()).hexdigest()
report={'passed':True,'raster_comparisons':rows,'godot_mobile':native,
    'render':render,
    'reported_v0_location_uv':{'x':[6.7,7.4],'y':[-2.1,-1.9]},'mineral_inset_m':.08}
(OUT/'outline-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
