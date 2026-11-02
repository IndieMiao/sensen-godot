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
for log in ['import.log','render.log']:
    text=(OUT/log).read_text()
    check(not re.search(r'(?:SCRIPT )?ERROR:',text),'No errors in '+log)
report['passed']=all(c['passed'] for c in report['checks'])
(OUT/'glb-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(len(report['checks']),'checks; passed:',report['passed'])
raise SystemExit(0 if report['passed'] else 1)
