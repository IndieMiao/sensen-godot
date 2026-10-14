"""Select uniform existing Deluxe atlas pixels inside actual kitchen mesh UVs."""
import sys,json,hashlib
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
atlas=ROOT/'assets/rooms/deluxe_room_10/room_albedo_ao.png'
im=np.array(Image.open(atlas).convert('RGB'));h,w=im.shape[:2]
spec={'sage':('sink_cabinet','7E8A65'),'honey':('kitchen_pantry','D59A53'),'brass':('kitchen_fittings','A8864C'),'cream':('kitchen_sink','F2E7D4'),'leaf':('all','78A84B')}
# List real kit candidates when a semantic module name changes.
assets=list((ROOT/'assets/rooms/deluxe_room_10').glob('*.glb'))
result={'atlas':'assets/props/warming_cabinet/room_albedo_ao.png','source_atlas':str(atlas.relative_to(ROOT)), 'atlas_sha256':hashlib.sha256(atlas.read_bytes()).hexdigest(),'swatches':{}}
for key,(name,color) in spec.items():
 paths=[p for p in assets if p.stem==name] or assets
 target=np.array([int(color[i:i+2],16) for i in (0,2,4)])
 best=None
 for path in paths:
  d,b=load_glb(path)
  for mi,m in enumerate(d['meshes']):
   for pi,p in enumerate(m['primitives']):
    if 'TEXCOORD_0' not in p['attributes']:continue
    uv=np.array(accessor(d,b,p['attributes']['TEXCOORD_0']));idx=np.array(accessor(d,b,p['indices'])).reshape(-1,3)
    for ti,t in enumerate(idx):
     c=uv[t].mean(0);xytri=uv[t]*[w,h];pcenter=c*[w,h]
     x,y=pcenter.astype(int);patch=im[y-3:y+4,x-3:x+4].astype(float)
     if patch.shape!=(7,7,3) or patch.min()<16:continue
     err=np.linalg.norm(im[y,x].astype(float)-target)+np.max(patch.std(axis=(0,1)))*3
     if best is None or err<best[0]:best=(err,path,mi,pi,ti,x,y,patch,c)
 err,path,mi,pi,ti,x,y,patch,c=best
 rec={'source_asset':str(path.relative_to(ROOT)),'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'source_mesh':mi,'source_primitive':pi,'source_triangle':ti,'pixel_xy':[int(x),int(y)],'gltf_uv':c.tolist(),'rgb8':im[y,x].tolist(),'patch_min':patch.min(axis=(0,1)).astype(int).tolist(),'patch_max':patch.max(axis=(0,1)).astype(int).tolist()}
 result['swatches'][key]=rec;print(key,rec['source_asset'],rec['rgb8'],[x,y])
(Path(__file__).parent/'atlas-swatches.json').write_text(json.dumps(result,indent=2)+'\n')
