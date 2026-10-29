#!/usr/bin/env python3
"""Brighten only the back-wall-exclusive texels behind the removed sign bracket."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import numpy as np
from PIL import Image
from verify_chef_sign import load_glb, accessor

ROOT=Path(__file__).resolve().parents[2]
KIT=ROOT/'assets/rooms/tavern'
OUT=ROOT/'output/npc-batch3/tavern'
SOURCE=ROOT/'tools/art/source/npc_batch3'
parser=argparse.ArgumentParser();parser.add_argument('--runtime-root',type=Path,required=True)
args=parser.parse_args()
baseline=args.runtime_root/'output/npc-batch3/tavern-original.png'
original=np.array(Image.open(baseline).convert('RGBA'))
doc,binary=load_glb(KIT/'back_wall.glb');prim=doc['meshes'][0]['primitives'][0]
xyz=np.array(accessor(doc,binary,prim['attributes']['POSITION']))
uv=np.array(accessor(doc,binary,prim['attributes']['TEXCOORD_0']))
indices=np.array(accessor(doc,binary,prim['indices'])).ravel().reshape(-1,3)
faces=indices[np.all(abs(xyz[indices,2]-.09)<1e-5,axis=1)]
used=np.unique(faces)
matrix=np.column_stack([xyz[used,:2],np.ones(len(used))])
mapping=np.linalg.lstsq(matrix,uv[used],rcond=None)[0]
residual=np.abs(matrix@mapping-uv[used]).max()
assert residual<1e-5,('Front plane is not a single affine UV island',residual)
height,width=original.shape[:2]
yy,xx=np.mgrid[:height,:width]
texels=np.stack([(xx+.5)/width,(yy+.5)/height,np.ones_like(xx)],axis=-1)
inverse=np.linalg.inv(np.column_stack([mapping,[0,0,1]]))
positions=texels@inverse
x,y=positions[...,0],positions[...,1]
def smooth(a):return np.clip(a,0,1)**2*(3-2*np.clip(a,0,1))
blend=smooth((x+.32)/.12)*smooth((.38-x)/.12)*smooth((y-3.02)/.12)*smooth((3.70-y)/.10)
safe=np.array(Image.open(OUT/'back-wall-safe-8px.png'))>0
blend*=safe
mask=blend>0
assert 0<mask.sum()<4000
def sample(world_x,world_y):
    mapped=np.stack([np.full_like(world_y,world_x),world_y,np.ones_like(world_y)],axis=-1)@mapping
    q=mapped*[width,height]-.5
    x0=np.floor(q[...,0]).astype(int);y0=np.floor(q[...,1]).astype(int)
    fx=q[...,0]-x0;fy=q[...,1]-y0
    x0=np.clip(x0,0,width-2);y0=np.clip(y0,0,height-2)
    return (original[y0,x0,:3]*(1-fx)[...,None]*(1-fy)[...,None]+
            original[y0,x0+1,:3]*fx[...,None]*(1-fy)[...,None]+
            original[y0+1,x0,:3]*(1-fx)[...,None]*fy[...,None]+
            original[y0+1,x0+1,:3]*fx[...,None]*fy[...,None])
selected_y=y[mask];selected_x=x[mask]
left,right=sample(-.48,selected_y),sample(.53,selected_y)
t=np.clip((selected_x+.48)/1.01,0,1)
target=left*(1-t[:,None])+right*t[:,None]
rgb=original[...,:3].astype(float);luma=np.array([.2126,.7152,.0722])
gain=np.maximum((target@luma)/np.maximum(rgb[mask]@luma,1),1)
result=original.copy()
result[...,:3][mask]=np.clip(np.rint(rgb[mask]*(1+(gain-1)*blend[mask])[:,None]),0,255).astype(np.uint8)
changed=np.any(result!=original,axis=2)
other=np.array(Image.open(OUT/'other-assets-uv.png'))>0
assert not np.any(changed&other)
assert np.array_equal(result[~mask],original[~mask])
assert np.array_equal(result[...,3],original[...,3])
ys,xs=np.where(changed)
Image.fromarray(result).save(KIT/'room_albedo_ao.png')
Image.fromarray(result).save(args.runtime_root/'assets/rooms/tavern/room_albedo_ao.png')
Image.fromarray((changed*255).astype(np.uint8)).save(SOURCE/'tavern-ao-357-mask.png')
report={'method':'Preserve source RGB ratios; softly raise only the bracket-shadow region toward same-height left/right timber samples.',
        'world_rectangle_xy':[-.32,3.02,.38,3.70],'source_sampling_x_m':[-.48,.53],
        'changed_pixels':int(changed.sum()),'changed_pixel_bounds_xyxy':[int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)],
        'other_assets_and_batches_pixels_changed':int((changed&other).sum()),'8px_other_asset_gutter_preserved':True,
        'alpha_exact':True,'outside_mask_exact':True,'front_plane_uv_residual':float(residual),
        'original_png_sha256':hashlib.sha256(baseline.read_bytes()).hexdigest(),
        'new_png_sha256':hashlib.sha256((KIT/'room_albedo_ao.png').read_bytes()).hexdigest(),
        'original_png_bytes':baseline.stat().st_size,'new_png_bytes':(KIT/'room_albedo_ao.png').stat().st_size,
        'glb_reexports':[],'all_glb_geometry_and_uv_unchanged':True,'runtime_png_exception_approved':True}
for path in KIT.rglob('*.glb'):
    relative=str(path.relative_to(ROOT))
    assert path.read_bytes()==subprocess.check_output(['git','show','HEAD:'+relative],cwd=ROOT)
(SOURCE/'tavern-ao-357-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
