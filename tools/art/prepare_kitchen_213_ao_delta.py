#!/usr/bin/env python3
"""Pillow/NumPy: turn paired AO bakes into a restricted reproducible source delta."""
import json,sys,subprocess,hashlib
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_chef_sign import load_glb,accessor
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/kitchen-213';SRC=ROOT/'tools/art/source/kitchen_213';KIT=ROOT/'assets/rooms/basic_room';BASE='154ce6421448e26e42ee225ba7018638ae756394'
layout=json.loads(subprocess.check_output(['git','show',BASE+':assets/rooms/basic_room/layout.json'],cwd=ROOT));targets=['room_shell','window_wall','back_wall','sink_cabinet','utensil_crock','wall_shelf','shelf_plant'];mask=Image.new('L',(2048,2048));draw=ImageDraw.Draw(mask)
for row in layout['assets']:
 if row['name'] not in targets:continue
 d,b=load_glb(KIT/row['file']);theta=np.deg2rad(row['yaw_degrees']);rot=np.array([[np.cos(theta),0,np.sin(theta)],[0,1,0],[-np.sin(theta),0,np.cos(theta)]])
 for mesh in d['meshes']:
  for pr in mesh['primitives']:
   pos=np.array(accessor(d,b,pr['attributes']['POSITION']))@rot.T+row['position'];uv=np.array(accessor(d,b,pr['attributes']['TEXCOORD_0']))*2048;ix=np.array(accessor(d,b,pr['indices'])).reshape(-1,3)
   # Include only triangles in the back-left kitchen region. Fixed UV seams
   # keep these from touching other walls/floorboards. A large face may span
   # the room; exact per-pixel barycentric coordinates limit its affected area.
   for inds in ix:
    xy=uv[inds];world=pos[inds];lo=np.maximum(np.floor(xy.min(0)).astype(int),0);hi=np.minimum(np.ceil(xy.max(0)).astype(int),2047)
    if np.any(hi<lo):continue
    xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1)+.5,np.arange(lo[1],hi[1]+1)+.5);v0=xy[1]-xy[0];v1=xy[2]-xy[0];den=v0[0]*v1[1]-v1[0]*v0[1]
    if abs(den)<1e-10:continue
    px=xx-xy[0,0];py=yy-xy[0,1];u=(px*v1[1]-v1[0]*py)/den;v=(v0[0]*py-px*v0[1])/den
    wx=world[0,0]+u*(world[1,0]-world[0,0])+v*(world[2,0]-world[0,0]);wz=world[0,2]+u*(world[1,2]-world[0,2])+v*(world[2,2]-world[0,2]);inside=(u>=0)&(v>=0)&(u+v<=1)&(wx<1)&(wz< -1)
    patch=Image.fromarray((inside*255).astype(np.uint8));mask.paste(Image.fromarray(np.maximum(np.array(mask.crop((lo[0],lo[1],hi[0]+1,hi[1]+1))),np.array(patch))),(lo[0],lo[1]))
allowed=np.array(mask.filter(ImageFilter.MaxFilter(17)))>0
old=np.array(Image.open(OUT/'ao-old.png').convert('RGB'))[:,:,0]/255.;new=np.array(Image.open(OUT/'ao-new.png').convert('RGB'))[:,:,0]/255.
def linear(a):return np.where(a<=.04045,a/12.92,((a+.055)/1.055)**2.4)
valid=allowed&(old>.05)&(new>.05);ratio=np.ones(old.shape);ratio[valid]=np.clip(linear(new[valid])/linear(old[valid]),.42,1/.42)
# Ignore sub-percent Monte Carlo changes; store immutable sparse delta for
# byte-identical regular rebuilds. Paired bake is an explicit optional refresh.
ratio[abs(ratio-1)<.025]=1
sw=json.loads((SRC/'atlas-swatches.json').read_text())
for swatch in sw['swatches'].values():
 x,y=swatch['pixel_xy'];ratio[y-5:y+6,x-5:x+6]=1
np.savez_compressed(SRC/'atlas-ao-delta.npz',factor=ratio.astype(np.float32),allowed=allowed)
report={'method':'Same original GLB UVs; paired Cycles EMIT bake of 0.42 + 0.58*AO, distance 0.68 m, 64 AO samples, 32 Cycles samples. Linear-light new/old ratio only in back-left kitchen target triangles (x<1,z<-1), 8 px bake gutter. <2.5% ratio changes ignored; palette samples protected.','targets':targets,'affected_pixels':int((ratio!=1).sum()),'min_factor':float(ratio.min()),'max_factor':float(ratio.max()),'source_baseline':BASE,'bakes':{v:hashlib.sha256((OUT/('ao-'+v+'.png')).read_bytes()).hexdigest() for v in ['old','new']},'delta_sha256':hashlib.sha256((SRC/'atlas-ao-delta.npz').read_bytes()).hexdigest()}
(SRC/'atlas-ao-delta.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
