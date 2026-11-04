"""Independent GLB, scale, palette and importer checks for the final-size marker."""
from pathlib import Path
import configparser
import hashlib
import json
import sys
import numpy as np

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/props/fish_trap_marker';OUT=ROOT/'output/trap-402'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
path=KIT/'fish_trap_marker.glb';doc,data=load_glb(path);spec=json.loads((KIT/'manifest.json').read_text());checks=[]
def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)
def linear(value):
    c=np.array(list(bytes.fromhex(value)))/255
    return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
check(len(doc['meshes'])==1 and doc['meshes'][0]['name']=='fish_trap_marker_mobile','One named mobile mesh')
prims=doc['meshes'][0]['primitives'];check(len(prims)==1,'One surface')
p=prims[0];attrs=p['attributes'];points=np.array(accessor(doc,data,attrs['POSITION']));normals=np.array(accessor(doc,data,attrs['NORMAL']))
colors=np.array(accessor(doc,data,attrs['COLOR_0']));tri=np.array(accessor(doc,data,p['indices'])).reshape(-1,3)
lo=points.min(axis=0);hi=points.max(axis=0)
check(len(tri)==spec['triangles']==500 and len(tri)<=500,'Actual 500 triangles, within 500 budget')
check(np.allclose([lo,hi],[[-.225,-.05,-.225],[.225,.38,.225]],atol=1e-6),'Actual bounds retain final .45m width / .38m above / .05m below water')
check(np.allclose([lo,hi],spec['bounds'],atol=1e-6),'Manifest matches actual vertex bounds')
check(np.allclose(lo[[0,2]]+hi[[0,2]],0,atol=1e-6),'Waterline origin horizontally centered')
check(set(attrs)=={'POSITION','NORMAL','COLOR_0'},'Only positions, normals and vertex colors; no texture channels or skin weights')
check(not doc.get('textures') and not doc.get('images'),'No textures')
check(not doc.get('animations') and not doc.get('skins'),'No skeleton or baked animation')
check(np.isfinite(points).all() and np.allclose(np.linalg.norm(normals,axis=1),1,atol=1e-5),'Finite geometry and unit normals')
area=np.linalg.norm(np.cross(points[tri[:,1]]-points[tri[:,0]],points[tri[:,2]]-points[tri[:,0]]),axis=1)
check(np.all(area>1e-10),'No degenerate triangles')
check(np.allclose(colors[:,3],1) and colors.min()>=0 and colors.max()<=1,'Opaque linear vertex color payload')
palette=np.array([linear(c) for c in spec['palette_srgb'].values()])
check(np.max(np.min(np.max(abs(colors[:,:3,None]-palette.T[None,:,:]),axis=1),axis=1))<.00004,'Only documented palette colors')
coral=np.max(abs(colors[:,:3]-linear('E07A5F')),axis=1)<.00004
check(coral.sum()>20,'Coral matches i-trap #E07A5F in linear values')
check(abs(np.ptp(points[coral,0])-.30)<1e-6 and abs(np.ptp(points[coral,2])-.30)<1e-6,'Actual coral buoy width .30m, 37 percent wider than native .21838m bobber')
wood_roles=['wicker_recess','wicker_strip','wicker_band','wicker_rim']
wood=np.min([np.max(abs(colors[:,:3]-linear(spec['palette_srgb'][role])),axis=1) for role in wood_roles],axis=0)<.00004
check(abs(points[wood,1].max()-.10)<1e-6 and points[wood,1].max()-.012>.08,'Woven dome stays at least .088m above water at bottom of existing bob')
for node in doc['nodes']:
    if 'mesh' in node:
        check(node.get('translation',[0,0,0])==[0,0,0] and node.get('scale',[1,1,1])==[1,1,1]
              and node.get('rotation',[0,0,0,1])==[0,0,0,1],'Baked unit node transform')
check(len(doc['materials'])==1,'One material')
mat=doc['materials'][0];pbr=mat['pbrMetallicRoughness']
check(pbr.get('metallicFactor',1)==0 and pbr.get('roughnessFactor',1)>=.85 and mat.get('alphaMode','OPAQUE')=='OPAQUE','Opaque matte, non-metallic material')
check(not mat.get('doubleSided',False),'Correct exterior winding, no blanket two-sided material')
cfg=configparser.ConfigParser(interpolation=None);cfg.read(KIT/'fish_trap_marker.glb.import')
check(cfg['remap']['uid'].startswith('"uid://'),'GLB importer UID present')
check(cfg['params']['gltf/texture_map_mode']=='1','texture_map_mode=1')
check(cfg['params']['animation/import']=='false' and cfg['params']['meshes/create_shadow_meshes']=='false','Static asset; no shadow mesh import')
check(json.loads(cfg['params']['import_script/path'])=='res://assets/props/fish_trap_marker/material_import.gd','Delivered colour/no-shadow import hook assigned')
check((KIT/'material_import.gd.uid').read_text().startswith('uid://'),'Import script UID delivered')
check(hashlib.sha256(path.read_bytes()).hexdigest()==spec['sha256'],'Manifest SHA-256 matches actual GLB')
snapshot=json.loads((OUT/'runtime-base.json').read_text())
check(all(hashlib.sha256((OUT/'project'/p).read_bytes()).hexdigest()==h for p,h in snapshot['files'].items()),'Critical b1 pond, bobber, water and UI files are unchanged in isolated project')
check((OUT/'project/assets/props/fish_trap_marker/fish_trap_marker.glb').read_bytes()==path.read_bytes(),'Render fixture uses exact delivered model bytes')
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','checks':checks,
    'triangles':len(tri),'surfaces':1,'bounds':[lo.tolist(),hi.tolist()],'buoy_width_m':float(np.ptp(points[coral,0])),
    'dome_above_low_bob_m':float(points[wood,1].max()-.012),'sha256':spec['sha256'],'runtime':snapshot,
    'passed':all(c['passed'] for c in checks)}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(len(checks),'checks; passed:',report['passed']);raise SystemExit(0 if report['passed'] else 1)
