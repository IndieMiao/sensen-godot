"""Blender BVH audit of actual GLBs at all six straight joints and the corner.

Tests wall-height joint closure both along the facade normal (worst case for
looking through a slot) and at the approved 45/33 camera direction.
"""
from pathlib import Path
import sys,json,math,subprocess
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[4];sys.path.insert(0,str(Path(__file__).parent))
from verify import read,array
BASE='c7a0a4b6a';ASSETS=ROOT/'assets/rooms/market_plaza'
layout=json.loads((ASSETS/'layout.json').read_text())
camera=Vector((math.sin(math.radians(45))*math.cos(math.radians(33)),math.sin(math.radians(33)),math.cos(math.radians(45))*math.cos(math.radians(33))))
def tree(variant,stage):
 vertices=[];polys=[]
 for p in layout['assets']:
  if p.get('group')!='FarFacades':continue
  filename=p['variants'][variant];raw=(ASSETS/filename).read_bytes() if stage=='after' else subprocess.check_output(['git','show',BASE+':assets/rooms/market_plaza/'+filename],cwd=ROOT)
  d,b=read(raw);prim=d['meshes'][0]['primitives'][0];v=array(d,b,prim['attributes']['POSITION']).astype(float);ix=array(d,b,prim['indices']).reshape(-1,3)
  angle=math.radians(p['yaw_degrees']);rot=np.array([[math.cos(angle),0,math.sin(angle)],[0,1,0],[-math.sin(angle),0,math.cos(angle)]])
  v=v@rot.T+np.array(p['position']);offset=len(vertices);vertices.extend(v.tolist());polys.extend((ix+offset).tolist())
 return BVHTree.FromPolygons(vertices,polys,all_triangles=True,epsilon=0)
seams=[(f'north_{x}',Vector((x,0,-8)),Vector((0,0,1)),Vector((1,0,0))) for x in [-4,0,4]]
seams += [(f'west_{z}',Vector((-8,0,z)),Vector((1,0,0)),Vector((0,0,1))) for z in [-4,0,4]]
seams += [('corner',Vector((-8,0,-8)),Vector((1,0,1)).normalized(),Vector((1,0,-1)).normalized())]
report={'base':BASE,'height_range_m':[.15,6.00],'height_step_m':.05,'height_scope':'common wall below the lower 6m eave plus 0.05m placement; above the low roof is intentionally open skyline','cross_joint_offsets_m':[-.02,-.01,0,.01,.02],'camera_yaw_pitch':[45,33],'variants':{}}
for variant in ['san_francisco','generic']:
 result={}
 for stage in ['before','after']:
  bvh=tree(variant,stage);rows=[]
  for name,point,normal,across in seams:
   counts={}
   for label,direction in [('normal',normal),('camera',camera)]:
    misses=[];total=0
    for iy in range(3,121):
     for dx in [-.02,-.01,0,.01,.02]:
      at=point+Vector((0,iy*.05,0))+across*dx;origin=at+direction*10
      hit,_,_,dist=bvh.ray_cast(origin,-direction,25);total+=1
      # A local building face must be present within 0.25m behind the seam.
      if hit is None or dist>10.25:misses.append([float(at.x),float(at.y),float(at.z)])
    counts[label]={'samples':total,'missing_local_wall':len(misses),'missing_points':misses}
    if stage=='after':assert not misses,(variant,name,label,misses[:4])
   rows.append({'joint':name,**counts})
  result[stage]=rows
 report['variants'][variant]=result
out=ROOT/'docs/design/market-facade-seams-218-2026-11-13';out.mkdir(parents=True,exist_ok=True);(out/'joint-rays.json').write_text(json.dumps(report,indent=2)+'\n')
for v,r in report['variants'].items():
 print(v,[(s,sum(x['normal']['missing_local_wall'] for x in rows),sum(x['camera']['missing_local_wall'] for x in rows)) for s,rows in r.items()])
print('JOINT_RAYS_PASS all 14 wall joints closed in normal and 45/33 directions')
