"""Measure final GLB vertex payload, import contract and unchanged farm assets."""
from pathlib import Path
import configparser
import hashlib
import json
import subprocess
import sys
import numpy as np

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/farm/art';OUT=ROOT/'output/flax-408'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
path=KIT/'flax_patch.glb';doc,data=load_glb(path)
manifest=json.loads((KIT/'manifest.json').read_text());spec=manifest['assets']['flax_patch'];checks=[]
def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)
def linear(value):
    c=np.array(list(bytes.fromhex(value)))/255
    return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
check(len(doc['meshes'])==1 and doc['meshes'][0]['name']=='flax_patch_mobile','One named mobile mesh')
prims=doc['meshes'][0]['primitives'];check(len(prims)==1,'One surface')
p=prims[0];attrs=p['attributes'];points=np.array(accessor(doc,data,attrs['POSITION']));normals=np.array(accessor(doc,data,attrs['NORMAL']))
colors=np.array(accessor(doc,data,attrs['COLOR_0']));tri=np.array(accessor(doc,data,p['indices'])).reshape(-1,3)
lo=points.min(axis=0);hi=points.max(axis=0);size=hi-lo
check(len(tri)==spec['triangles']==894 and len(tri)<=900,'894 triangles within 900 budget')
check(1.2<=size[0]<=1.4 and 1.2<=size[2]<=1.4 and .6<=size[1]<=.7,'Measured footprint / height meet brief')
check(np.allclose([lo,hi],spec['bounds'],atol=1e-6),'Manifest matches actual vertex bounds')
check(np.allclose(lo[[0,2]]+hi[[0,2]],0,atol=1e-6) and abs(lo[1])<1e-7,'Bottom-centre origin')
check(set(attrs)=={'POSITION','NORMAL','COLOR_0'},'No texture channels or skin weights')
check(not doc.get('textures') and not doc.get('images'),'No textures')
check(not doc.get('animations') and not doc.get('skins'),'No skeleton or animation')
check(np.isfinite(points).all() and np.allclose(np.linalg.norm(normals,axis=1),1,atol=1e-5),'Finite geometry and unit normals')
area=np.linalg.norm(np.cross(points[tri[:,1]]-points[tri[:,0]],points[tri[:,2]]-points[tri[:,0]]),axis=1)
check(np.all(area>1e-10),'No degenerate triangles')
check(np.allclose(colors[:,3],1) and colors.min()>=0 and colors.max()<=1,'Opaque vertex colors')
palette=np.array([linear(c) for c in spec['palette_srgb'].values()])
check(np.max(np.min(np.max(abs(colors[:,:3,None]-palette.T[None,:,:]),axis=1),axis=1))<.00004,'Only documented linear palette values')
blue=np.min([np.max(abs(colors[:,:3]-linear(spec['palette_srgb'][role])),axis=1)
             for role in ['blue','blue_light','blue_shade']],axis=0)<.00004
check(points[blue,1].min()>.47 and np.ptp(points[blue,0])>.9 and np.ptp(points[blue,2])>.9,
      'Blue flower crowns distributed across upper patch, not hidden at roots')
for node in doc['nodes']:
    if 'mesh' in node:
        check(node.get('translation',[0,0,0])==[0,0,0] and node.get('scale',[1,1,1])==[1,1,1]
              and node.get('rotation',[0,0,0,1])==[0,0,0,1],'Baked unit node transform')
check(len(doc['materials'])==1,'One material')
reference,_=load_glb(KIT/'sign.glb')
check(doc['materials']==reference['materials'],'GLB material matches sign.glb exactly')
cfg=configparser.ConfigParser(interpolation=None);cfg.read(KIT/'flax_patch.glb.import')
ref=configparser.ConfigParser(interpolation=None);ref.read(KIT/'sign.glb.import')
check(cfg['remap']['uid'].startswith('"uid://') and cfg['remap']['uid']!=ref['remap']['uid'],'Unique GLB importer UID')
def nonnull(section): return {k:v for k,v in section.items() if v!='null'}
check(nonnull(cfg['params'])==nonnull(ref['params']),'Importer parameters match sign.glb.import (Godot omits null fields), including light_baking=1')
check(hashlib.sha256(path.read_bytes()).hexdigest()==spec['sha256'],'Manifest SHA-256 matches actual GLB')
baseline=json.loads(subprocess.check_output(['git','show','caef42a073ce20a7bb16b9414b9026316c9587f6:assets/farm/art/manifest.json'],cwd=ROOT))
without=json.loads(json.dumps(manifest));del without['assets']['flax_patch']
check(without==baseline,'Manifest appends flax only; all prior entries unchanged')
changed=subprocess.check_output(['git','diff','--name-only','caef42a073ce20a7bb16b9414b9026316c9587f6','--','assets/farm/art'],cwd=ROOT,text=True).splitlines()
check(set(changed)<={'assets/farm/art/manifest.json','assets/farm/art/flax_patch.glb','assets/farm/art/flax_patch.glb.import'},'No existing farm meshes or imports changed')
check((OUT/'project/assets/farm/art/flax_patch.glb').read_bytes()==path.read_bytes(),'Review uses exact delivered GLB')
runtime=json.loads((OUT/'runtime-base.json').read_text())
critical=['scenes/p0/p0_pond.gd','scenes/p0/p0_ui.gd','modules/farm/farm_art.gd','modules/farm/crop_plant_mesh.gd','modules/mining/mine_mesh.gd']
hashes={}
for name in critical:
    original=subprocess.check_output(['git','show',runtime['runtime_commit']+':'+name],cwd=ROOT)
    check((OUT/'project'/name).read_bytes()==original,'Private review preserves b1 '+name)
    hashes[name]=hashlib.sha256(original).hexdigest()
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','checks':checks,
    'triangles':len(tri),'surfaces':1,'bounds':[lo.tolist(),hi.tolist()],'dimensions_xyz':size.tolist(),
    'sha256':spec['sha256'],'runtime':runtime,'runtime_unchanged_files_sha256':hashes,
    'passed':all(c['passed'] for c in checks)}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(len(checks),'checks; passed:',report['passed']);raise SystemExit(0 if report['passed'] else 1)
