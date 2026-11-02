"""Independent GLB, import and review checks for the SGODOT-355 static kit."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import re
import shutil
import sys

ROOT=Path(__file__).resolve().parents[4]
RUNTIME=ROOT/'output/monsters-355/runtime'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb, accessor, cross, sub

parser=argparse.ArgumentParser()
parser.add_argument('group',choices=['headgear','mine_props'])
args=parser.parse_args()
OUT=ROOT/'output/mine-kit-355'/args.group
directories=['assets/monsters/slime_king'] if args.group=='headgear' else ['assets/mine/rocks','assets/mine/props']
report={'checks':[],'assets':[]}
def check(ok,label):
    report['checks'].append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)

for directory in directories:
    manifest=json.loads((RUNTIME/directory/'manifest.json').read_text())
    for spec in manifest['assets']:
        name=spec['name'];path=RUNTIME/spec['file'];doc,data=load_glb(path)
        check(len(doc.get('meshes',[]))==1 and len(doc['meshes'][0]['primitives'])==1,name+': single mesh / surface')
        check(doc['meshes'][0]['name']==name+'_mobile',name+': named mesh')
        check(not doc.get('skins') and not doc.get('animations'),name+': no skin or animation')
        check(len(doc.get('materials',[]))==1 and not doc.get('images') and not doc.get('textures'),name+': one untextured material')
        primitive=doc['meshes'][0]['primitives'][0]
        check(set(primitive['attributes'])=={'POSITION','NORMAL','COLOR_0'},name+': geometry / normals / vertex colours only')
        positions=accessor(doc,data,primitive['attributes']['POSITION'])
        normals=accessor(doc,data,primitive['attributes']['NORMAL'])
        colors=accessor(doc,data,primitive['attributes']['COLOR_0'])
        indices=[v[0] for v in accessor(doc,data,primitive['indices'])]
        check(len(indices)//3==spec['triangles'] and len(indices)//3<=spec['triangle_limit'],name+': measured triangle count / budget')
        check(all(len(c)==3 or abs(c[3]-1)<1e-6 for c in colors),name+': opaque colours')
        check(all(abs(math.sqrt(sum(v*v for v in n))-1)<.0001 for n in normals),name+': unit normals')
        bounds=[[min(v[i] for v in positions) for i in range(3)],[max(v[i] for v in positions) for i in range(3)]]
        check(all(abs(bounds[j][i]-spec['bounds'][j][i])<1e-6 for i in range(3) for j in range(2)),name+': actual vertex bounds match manifest')
        check(all(n.get('scale',[1,1,1])==[1,1,1] for n in doc['nodes']),name+': unit scales')
        mesh_node=next(n for n in doc['nodes'] if 'mesh' in n)
        check(mesh_node.get('translation',[0,0,0])==[0,0,0] and mesh_node.get('rotation',[0,0,0,1])==[0,0,0,1],name+': geometry baked around declared origin')
        degenerate=0;inverted=0
        for i in range(0,len(indices),3):
            tri=indices[i:i+3];a,b,c=[positions[j] for j in tri];normal=cross(sub(b,a),sub(c,a))
            if sum(v*v for v in normal)<1e-18:degenerate+=1
            average=[sum(normals[j][axis] for j in tri) for axis in range(3)]
            if sum(x*y for x,y in zip(normal,average))< -1e-9:inverted+=1
        check(degenerate==0 and inverted==0,name+': nondegenerate triangles and consistent winding')
        if args.group=='mine_props':
            check(abs(bounds[0][1])<1e-6,name+': ground origin')
            if name.startswith('rock_'):
                check(max(math.hypot(p[0],p[2]) for p in positions)<=.48 and .62<=bounds[1][1]<=.64,name+': code-scale radius and height')
            elif name=='guard_arena':
                check(bounds[1][0]-bounds[0][0]<=7 and bounds[1][2]-bounds[0][2]<=4.5,name+': footprint budget')
                high=[p for p in positions if p[1]>.25]
                check(all(2.7<=p[0]+4.9<=6.8 and p[2]<-1.7 and p[1]<=1.6 for p in high),name+': all tall geometry in authorized rear strip')
                check(all(math.hypot(p[0]+4.9-x,p[2]-3.8-z)>=1.6 for p in high for x,z in [(1.25,-6.75),(8.25,-6.75)]),name+': tall geometry clears both transport anchors')
                from shapely.geometry import Polygon, box
                overlap=0;inside=0
                elevator_base=box(1.25-.725,-6.75-.65,1.25+.725,-6.75+.65)
                for i in range(0,len(indices),3):
                    tri=[positions[j] for j in indices[i:i+3]]
                    poly=Polygon([(p[0]+4.9,p[2]-3.8) for p in tri])
                    if poly.area>1e-10 and poly.intersection(elevator_base).area>1e-10:overlap+=1
                    for u in range(7):
                        for v in range(7-u):
                            x=tri[0][0]+(tri[1][0]-tri[0][0])*u/6+(tri[2][0]-tri[0][0])*v/6
                            z=tri[0][2]+(tri[1][2]-tri[0][2])*u/6+(tri[2][2]-tri[0][2])*v/6
                            if (x/3)**2+(z/1.8)**2<1-1e-5:inside+=1
                check(overlap==0,name+': no triangle projection intersects elevator base')
                check(inside==0,name+': 6.0 x 3.6 ellipse remains empty at triangle samples')
            elif name=='elevator_station':
                check(bounds[1][1]<=2.3,name+': height <=2.3m')
                for anchor in spec['anchors']:
                    marker=next(n for n in doc['nodes'] if n.get('name')==anchor['name'])
                    check(all(abs(x-y)<1e-6 for x,y in zip(marker['translation'],anchor['position'])) and 'mesh' not in marker,name+': exact empty '+anchor['name'])
                    check(all(abs(x-y)<1e-6 for x,y in zip(marker.get('rotation',[0,0,0,1]),[0,0,0,1])),name+': '+anchor['name']+' faces +Z')
                def by_colour(hexcode):
                    rgb=[int(hexcode[i:i+2],16)/255 for i in [0,2,4]]
                    linear=[c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in rgb]
                    return [p for p,c in zip(positions,colors) if max(abs(c[i]-linear[i]) for i in range(3))<.00003]
                plate=by_colour('DFD8BA');backing=by_colour('775B46')
                front=max(p[2] for p in plate);back=max(p[2] for p in backing)
                check(front-back>=.03-1e-6 and abs(front-.51)<1e-6,name+': measured plate projects >=3cm from backing')
                check(abs(max(p[0] for p in plate)-min(p[0] for p in plate)-.5)<1e-6 and abs(max(p[1] for p in plate)-min(p[1] for p in plate)-.3)<1e-6,name+': measured blank plate 0.5 x 0.3m')
                planks=sum([by_colour(c) for c in ['B58C63','C19970','AF835C']],[])
                check(abs(max(p[1] for p in planks)-.17)<1e-6,name+': measured platform plank top .17m')
        imported=OUT/'project'/path.relative_to(RUNTIME)
        check(hashlib.sha256(imported.read_bytes()).hexdigest()==spec['sha256']==hashlib.sha256(path.read_bytes()).hexdigest(),name+': rendered GLB equals delivery hash')
        config=Path(str(imported)+'.import').read_text()
        check(bool(re.search(r'uid="uid://[^"]+"',config)),name+': generated import UID')
        for key in ['animation/import=false','animation/remove_immutable_tracks=false','meshes/ensure_tangents=false',
                'meshes/create_shadow_meshes=false','gltf/texture_map_mode=1','_subresources={}',
                'import_script/path="res://assets/monsters/material_import.gd"']:
            check(key in config,name+': '+key)
        shutil.copy2(Path(str(imported)+'.import'),Path(str(path)+'.import'))
        report['assets'].append({'name':name,'triangles':len(indices)//3,'bounds':bounds,'sha256':spec['sha256']})

godot=json.loads((OUT/'captures/godot-validation.json').read_text())
check(godot['passed'] and godot['renderer']['method']=='mobile','Completed Godot Mobile validation')
if args.group=='headgear':
    prior=ROOT/'docs/design/mine-kit-355-2026-11-02/headgear/SGODOT-355_slime_king_v1_validation.json'
    if prior.exists():
        previous=json.loads(prior.read_text())
        for name in godot['assets']:
            check(godot['assets'][name]['uid']==previous['godot']['assets'][name]['uid'],name+': v1 import UID preserved')
        approved=next(a for a in previous['manifest']['assets'] if a['name']=='crown')
        check(hashlib.sha256((RUNTIME/approved['file']).read_bytes()).hexdigest()==approved['sha256'],'Approved crown GLB unchanged from v1')
for log in ['import.log','render.log']:
    text=(OUT/log).read_text()
    check(not re.search(r'(?:SCRIPT )?ERROR:',text),'No errors in '+log)
report['passed']=all(c['passed'] for c in report['checks'])
(OUT/'glb-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(len(report['checks']),'checks; passed:',report['passed'])
raise SystemExit(0 if report['passed'] else 1)
