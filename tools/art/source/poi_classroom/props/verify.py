"""Independent validation of the delivered GLB buffers and local-pivot contract."""
from pathlib import Path
import configparser
import hashlib
import json
import sys
import numpy as np

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[4]
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
KIT=ROOT/'assets/rooms/poi_classroom/props';OUT=ROOT/'output/classroom-props-322'
manifest=json.loads((KIT/'prop_manifest.json').read_text())
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','checks':[],'assets':{}}
def check(ok,label):
    report['checks'].append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)

uids=[];unique=0;placed=0
check(len(manifest['assets'])==7 and sum(s['quantity'] for s in manifest['assets'])==9,'Seven unique / nine placed modules')
for spec in manifest['assets']:
    name=spec['name'];path=KIT/spec['file'];doc,data=load_glb(path)
    check(len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1,name+': one mesh / surface')
    check(doc['meshes'][0]['name']==name+'_mobile',name+': mobile mesh naming')
    check(len(doc['materials'])==1 and not doc.get('textures') and not doc.get('images'),name+': one material / no textures')
    mat=doc['materials'][0]['pbrMetallicRoughness']
    check(mat.get('roughnessFactor',1)>=.85 and mat.get('metallicFactor',1)==0,name+': matte nonmetallic')
    p=doc['meshes'][0]['primitives'][0];a=p['attributes']
    points=np.array(accessor(doc,data,a['POSITION']));idx=np.array(accessor(doc,data,p['indices'])).reshape(-1,3)
    colors=np.array(accessor(doc,data,a['COLOR_0']));normals=np.array(accessor(doc,data,a['NORMAL']))
    lo=points.min(axis=0);hi=points.max(axis=0);triangles=len(idx)
    check(triangles==spec['triangles'] and triangles<=600,name+': measured triangles <=600')
    check(np.allclose([lo,hi],spec['bounds'],atol=1e-5),name+': measured bounds match manifest')
    check(np.all(np.isfinite(points)) and np.allclose(np.linalg.norm(normals,axis=1),1,atol=1e-4),name+': finite geometry / unit normals')
    area=np.linalg.norm(np.cross(points[idx[:,1]]-points[idx[:,0]],points[idx[:,2]]-points[idx[:,0]]),axis=1)
    check(np.all(area>1e-12),name+': no degenerate triangles')
    check(np.all(colors>=0) and np.all(colors<=1) and np.allclose(colors[:,3],1),name+': opaque vertex colors')
    if spec['origin']=='bottom_center':
        check(abs(lo[1])<1e-5 and abs(lo[0]+hi[0])<1e-5 and abs(lo[2]+hi[2])<1e-5,name+': bottom-center pivot')
    else:check(abs(lo[2])<1e-5 and np.max(np.abs(lo[:2]+hi[:2]))<1e-5,name+': back-center pivot')
    check(not doc.get('animations') and not doc.get('skins'),name+': static prop')
    check(all(not n.get('name','').startswith(('seat_','npc_','use_')) for n in doc['nodes']),name+': no seat / NPC / use anchors')
    for node in doc['nodes']:
        if 'mesh' in node:
            check(node.get('translation',[0,0,0])==[0,0,0] and node.get('rotation',[0,0,0,1])==[0,0,0,1]
                and node.get('scale',[1,1,1])==[1,1,1],name+': baked unit transform')
    config=configparser.ConfigParser(interpolation=None);config.read(str(path)+'.import')
    uid=json.loads(config['remap'].get('uid','""'));uids.append(uid)
    check(uid.startswith('uid://') and config['params']['gltf/texture_map_mode']=='1',name+': UID / texture_map_mode=1')
    check(json.loads(config['params']['import_script/path'])=='res://assets/rooms/poi_classroom/props/material_import.gd',name+': vertex-color import hook')
    check((ROOT/spec['provenance']).exists(),name+': authored provenance')
    if name=='blackboard':check(1.8<=hi[0]-lo[0]<=2,'Blackboard width 1.8-2.0m')
    if name=='teacher_desk':
        rgb=np.array([229,198,160])/255;linear=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
        wood=np.max(np.abs(colors[:,:3]-linear),axis=1)<.00004
        check(wood.any() and abs(points[wood,1].max()-.65*1.745)<.0001,'Actual wood desktop at .65H = 1.13425m')
    if name=='name_sign':
        anchor=next(n for n in doc['nodes'] if n.get('name')=='sign_door')
        check(anchor['extras']['size'][1]>=.25 and np.allclose(anchor['extras']['size'],[1.30,.28]),'sign_door writable area 1.30 x .28m')
        check(np.allclose(anchor.get('translation'),spec['anchors'][0]['position'],atol=1e-5),'sign_door center exported')
        check(anchor['translation'][2]>hi[2],'Text anchor clears front of sign')
    report['assets'][name]={'triangles':triangles,'surfaces':1,'bounds':[lo.tolist(),hi.tolist()],
        'dimensions_m':(hi-lo).tolist(),'uid':uid,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    unique+=triangles;placed+=triangles*spec['quantity']
check(len(set(uids))==7,'Seven distinct import UIDs')
check(unique==manifest['unique_triangles'] and placed==manifest['placed_triangles'] and placed<=3000,'Budget includes repeated stationery and cushions')
report.update(unique_triangles=unique,placed_triangles=placed,placed_surfaces=9,passed=all(c['passed'] for c in report['checks']))
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(len(report['checks']),'checks; passed:',report['passed'],'triangles',unique,placed)
raise SystemExit(0 if report['passed'] else 1)
