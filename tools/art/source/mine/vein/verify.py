"""Audit the exported veil, protected silhouette, mask convention and palette."""
from pathlib import Path
import hashlib
import json
import math
import re
import shutil
import sys
import numpy as np
from shapely.geometry import Polygon
from shapely.ops import unary_union
from shapely import set_precision

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
RUNTIME=ROOT/'output/monsters-355/runtime';OUT=ROOT/'output/mine-vein-355'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor

report={'checks':[]}
def check(ok,label):
    report['checks'].append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)

path=RUNTIME/'assets/mine/types/vein/backdrop.glb';doc,data=load_glb(path)
primitive=doc['meshes'][0]['primitives'][0];attrs=primitive['attributes']
points=np.array(accessor(doc,data,attrs['POSITION']))
colors=np.array(accessor(doc,data,attrs['COLOR_0']))
mask=np.array(accessor(doc,data,attrs['TEXCOORD_1']))
indices=np.array([v[0] for v in accessor(doc,data,primitive['indices'])]).reshape(-1,3)
check(len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1,'One mesh and one surface')
check(len(indices)<=4000,'At most 4000 triangles')
check(not doc.get('images') and not doc.get('textures') and len(doc['materials'])==1,'One material and zero textures')
check('KHR_materials_unlit' in doc['materials'][0].get('extensions',{}),'Unlit data-preview material retained')
check(not doc.get('animations') and not doc.get('skins'),'No rig or animations')
check(all(n.get('translation',[0,0,0])==[0,0,0] and n.get('rotation',[0,0,0,1])==[0,0,0,1]
    and n.get('scale',[1,1,1])==[1,1,1] for n in doc['nodes']),'Identity node transforms; offset remains in runtime')
rock=mask[:,1]<.001;mineral=mask[:,1]>.999
check(np.all(rock|mineral) and np.any(rock) and np.any(mineral),'GLB UV2.y contains grayscale 0 and mineral 1')
check(np.all(np.ptp(colors[rock,:3],axis=1)<1e-6),'Non-mineral COLOR_0 is grayscale')
check(colors[rock,:3].min()>=.419 and colors[rock,:3].max()<=.961,'Rock grayscale in original .42-.96 range')
check(np.allclose(colors[:,3],1) if colors.shape[1]==4 else True,'Opaque vertex colours')
check(mask[:,0].min()>=-1e-6 and mask[:,0].max()<=1.000001,'UV2.x remains a 0..1 void fade')
check(np.any(np.all(colors[mineral,:3]>.90,axis=1)),'Quartz seam retains linear white above .90')
check(np.any(colors[mineral,0]>colors[mineral,1]*2),'Rust edge has authored linear colour')
normal=np.array([.183116,.681998,.708058]);depth=points@normal
check(depth.min()>=-6.97 and depth.max()<=-5.60,'All vertices within required camera-depth slab')
cross=np.cross(points[indices[:,1]]-points[indices[:,0]],points[indices[:,2]]-points[indices[:,0]])
check(np.all(np.linalg.norm(cross,axis=1)>1e-10),'No degenerate exported triangles')

pitch=math.radians(43);yaw=math.radians(14.5)
n=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch)])
right=np.array([math.cos(yaw),0,-math.sin(yaw)]);up=np.cross(n,right)
def footprint(file):
    d,b=load_glb(file);p=d['meshes'][0]['primitives'][0]
    positions=np.array(accessor(d,b,p['attributes']['POSITION']))
    projected=np.column_stack((positions@right,positions@up))
    idx=[row[0] for row in accessor(d,b,p['indices'])]
    polygons=[]
    for i in range(0,len(idx),3):
        poly=Polygon(projected[idx[i:i+3]])
        if poly.area>1e-10:polygons.append(set_precision(poly,.00001))
    union=unary_union(polygons)
    members=[union] if union.geom_type=='Polygon' else list(union.geoms)
    holes=[Polygon(ring) for polygon in members for ring in polygon.interiors]
    hole=max(holes,key=lambda p:p.area)
    # Float32 triangulation can leave hairline slits; remove only <0.1mm spikes.
    hole=hole.buffer(-.00005,join_style=2).buffer(.00005,join_style=2)
    return union,hole
before,old_hole=footprint(RUNTIME/'assets/mine/backdrop/mine_backdrop.glb')
after,new_hole=footprint(path)
distance=old_hole.hausdorff_distance(new_hole)
check(distance<.0001,'Protected inner contour unchanged within 0.1mm in projection')
check(old_hole.buffer(-.0001).intersection(after).area<1e-6,'No new geometry enters protected inner area')
report['protected_contour']={'original_area_m2':old_hole.area,'new_area_m2':new_hole.area,
    'hausdorff_distance_m':distance,'new_intrusion_m2':old_hole.buffer(-.0001).intersection(after).area,
    'projection_weld_grid_m':.00001,'hairline_cleanup_radius_m':.00005}
source=json.loads((OUT/'original-surface.json').read_text())
original_uv=np.unique(np.array([p[:2] for tri in source['triangles'] for p in tri['uvn']]),axis=0)
current_uv=np.column_stack((points@right,points@up));max_error=0.0
for start in range(0,len(original_uv),128):
    distances=np.linalg.norm(original_uv[start:start+128,None,:]-current_uv[None,:,:],axis=2)
    max_error=max(max_error,float(distances.min(axis=1).max()))
check(max_error<.00001,'Every original primary-surface vertex retained within 0.01mm in projection')
report['protected_contour']['max_primary_projected_vertex_error_m']=max_error
palette=json.loads((path.parent/'palette.json').read_text());bands=palette['bands']
check([(b['from'],b['to']) for b in bands]==[(1,10),(11,20),(21,30),(31,40)],'Continuous exact 1..40 layer bands')
check(all(set(b)=={'from','to','ground','wall','backdrop_tint','fog'} for b in bands),'Palette matches agreed schema')
check(all(re.fullmatch(r'#[0-9a-fA-F]{6}',b[key]) for b in bands for key in ['ground','wall','backdrop_tint','fog']),'All palette colours are six-digit hex')
def luminance(value):
    values=np.array([int(value[i:i+2],16)/255 for i in [1,3,5]])
    linear=np.where(values<=.04045,values/12.92,((values+.055)/1.055)**2.4)
    return float(linear@np.array([.2126,.7152,.0722]))
for key in ['ground','wall','backdrop_tint']:
    values=[luminance(b[key]) for b in bands]
    check(all(a>b for a,b in zip(values,values[1:])),key+' gets progressively darker')
check(all(b['fog'].lower()!='#000000' for b in bands),'Void stays nonblack; no real fog')
contrast=(luminance(bands[-1]['ground'])+.05)/(luminance('#333b43')+.05)
check(contrast>3,'Deepest ground contrasts with coal base colour by >3:1')
report['palette_luminance']={key:[luminance(b[key]) for b in bands] for key in ['ground','wall','backdrop_tint','fog']}
report['coal_palette_contrast']=contrast
report['geometry']={'triangles':len(indices),'surfaces':1,'depth_min':float(depth.min()),'depth_max':float(depth.max()),
    'bounds':[points.min(axis=0).tolist(),points.max(axis=0).tolist()],
    'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'mineral_vertices':int(mineral.sum()),'rock_vertices':int(rock.sum())}
config=OUT/'project/assets/mine/types/vein/backdrop.glb.import'
if config.exists():
    text=config.read_text();uid=re.search(r'^uid="([^"]+)"',text,re.M)
    check(uid is not None,'Godot generated import UID')
    check('import_script/path=""' in text,'No monster import script')
    for key in ['meshes/generate_lods=false','meshes/create_shadow_meshes=false','meshes/light_baking=0','gltf/texture_map_mode=1']:
        check(key in text,key)
    if uid:report['uid']=uid[1];shutil.copy2(config,Path(str(path)+'.import'))
report['passed']=all(c['passed'] for c in report['checks'])
(OUT/'glb-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(len(report['checks']),'checks; passed:',report['passed'])
raise SystemExit(0 if report['passed'] else 1)
