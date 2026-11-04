"""Independent final-payload measurements and farm import/preservation checks."""
from pathlib import Path
import colorsys
import configparser
import hashlib
import json
import subprocess
import sys
import numpy as np

SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/farm/art';OUT=ROOT/'output/reed-clay-416'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
manifest=json.loads((KIT/'manifest.json').read_text());checks=[];measurements={}
def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)
def linear(h):
    c=np.array(list(bytes.fromhex(h)))/255
    return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
ref,_=load_glb(KIT/'sign.glb');ref_cfg=configparser.ConfigParser(interpolation=None);ref_cfg.read(KIT/'sign.glb.import')
def params(c):return {k:v for k,v in c['params'].items() if v!='null'}
uids=[ref_cfg['remap']['uid']]
for name,expected,limit,h0,h1 in [('reed_bank',890,1.4,.8,1),('clay_pit',552,1.2,0,.5)]:
    path=KIT/(name+'.glb');doc,data=load_glb(path);spec=manifest['assets'][name]
    check(len(doc['meshes'])==1 and doc['meshes'][0]['name']==name+'_mobile',name+': one named mobile mesh')
    prims=doc['meshes'][0]['primitives'];check(len(prims)==1,name+': one surface')
    p=prims[0];attrs=p['attributes'];points=np.array(accessor(doc,data,attrs['POSITION']))
    normals=np.array(accessor(doc,data,attrs['NORMAL']));colors=np.array(accessor(doc,data,attrs['COLOR_0']))
    indices=np.array(accessor(doc,data,p['indices'])).reshape(-1,3);lo=points.min(axis=0);hi=points.max(axis=0);size=hi-lo
    check(len(indices)==spec['triangles']==expected and len(indices)<=900,name+': actual triangles within 900')
    check(size[0]<=limit+1e-6 and size[2]<=limit+1e-6 and h0<=size[1]<=h1+1e-6,name+': entire vertex bounds within dimensions')
    check(np.allclose([lo,hi],spec['bounds'],atol=1e-6),name+': manifest matches vertices')
    check(abs(lo[1])<1e-6 and np.allclose((lo+hi)[[0,2]],0,atol=1e-6),name+': bottom centre origin')
    check(set(attrs)=={'POSITION','NORMAL','COLOR_0'} and not doc.get('textures') and not doc.get('images'),name+': positions, normals, colours only')
    check(not doc.get('skins') and not doc.get('animations'),name+': no skeleton or animation')
    check(np.isfinite(points).all() and np.allclose(np.linalg.norm(normals,axis=1),1,atol=1e-5),name+': finite geometry and unit normals')
    area=np.linalg.norm(np.cross(points[indices[:,1]]-points[indices[:,0]],points[indices[:,2]]-points[indices[:,0]]),axis=1)
    check(np.all(area>1e-10),name+': no degenerate triangles')
    check(np.allclose(colors[:,3],1),name+': opaque vertex colours')
    palette=np.array([linear(c) for c in spec['palette_srgb'].values()])
    check(np.max(np.min(np.max(abs(colors[:,:3,None]-palette.T[None,:,:]),axis=1),axis=1))<.00004,name+': documented linear palette')
    check(doc['materials']==ref['materials'],name+': exact sign.glb material payload')
    check(all(n.get('translation',[0,0,0])==[0,0,0] and n.get('scale',[1,1,1])==[1,1,1]
              and n.get('rotation',[0,0,0,1])==[0,0,0,1] for n in doc['nodes']),name+': identity transforms')
    cfg=configparser.ConfigParser(interpolation=None);cfg.read(KIT/(name+'.glb.import'))
    check(params(cfg)==params(ref_cfg),name+': sign import settings; tangents/LOD true, light_baking=1')
    check(cfg['remap']['uid'].startswith('"uid://'),name+': UID present');uids.append(cfg['remap']['uid'])
    check(hashlib.sha256(path.read_bytes()).hexdigest()==spec['sha256'],name+': manifest SHA-256')
    check((OUT/'project/assets/farm/art'/(name+'.glb')).read_bytes()==path.read_bytes(),name+': exact review model bytes')
    details={'triangles':len(indices),'surfaces':1,'bounds':[lo.tolist(),hi.tolist()],'dimensions_xyz':size.tolist(),'sha256':spec['sha256']}
    if name=='reed_bank':
        leaf_roles=['reed','reed_light','reed_dark']
        leaves=np.min([np.max(abs(colors[:,:3]-linear(spec['palette_srgb'][r])),axis=1) for r in leaf_roles],axis=0)<.00004
        check(np.max(abs(points[leaves,0]))<=.7 and np.max(abs(points[leaves,2]))<=.7,'Reed: all leaf vertices within 1.4m footprint')
        check(spec['cattail_count']==6 and min(h['top_m'] for h in spec['cattail_heads'])>points[leaves,1].max(),'Reed: six brown heads higher than leaf tips')
        details['leaf_top_m']=float(points[leaves,1].max());details['shortest_head_top_m']=min(h['top_m'] for h in spec['cattail_heads'])
    else:
        check(spec['clay_blocks']==2,'Clay: only two small clay blocks')
        clay_rgb=np.array(list(bytes.fromhex(spec['palette_srgb']['clay'])))/255
        coral_rgb=np.array(list(bytes.fromhex('E07A5F')))/255
        details['clay_hsv']=list(colorsys.rgb_to_hsv(*clay_rgb));details['trap_coral_hsv']=list(colorsys.rgb_to_hsv(*coral_rgb))
    measurements[name]=details
check(len(set(uids))==3,'Both new UIDs distinct from each other and sign')
snapshot=json.loads((OUT/'runtime-base.json').read_text())
baseline=json.loads(subprocess.check_output(['git','show',snapshot['art_base']+':assets/farm/art/manifest.json'],cwd=ROOT))
old=json.loads(json.dumps(manifest))
for name in ['reed_bank','clay_pit']:del old['assets'][name]
check(old==baseline,'Manifest appends two entries; old entries unchanged')
allowed={'assets/farm/art/manifest.json'}|{'assets/farm/art/'+n+s for n in ['reed_bank','clay_pit'] for s in ['.glb','.glb.import']}
changed=set(subprocess.check_output(['git','diff','--name-only',snapshot['art_base'],'--','assets/farm/art'],cwd=ROOT,text=True).splitlines())
check(changed<=allowed,'Existing farm assets and imports unchanged')
for path,digest in snapshot['files'].items():
    check(hashlib.sha256((OUT/'project'/path).read_bytes()).hexdigest()==digest,'Native b1 unchanged: '+path)
for path,source in snapshot['comparison_assets'].items():
    if path.endswith('.import'):continue
    check(hashlib.sha256((OUT/'project'/path).read_bytes()).hexdigest()==source['sha256'],'Pinned comparison unchanged: '+path)
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','checks':checks,'assets':measurements,
        'runtime':snapshot,'passed':all(c['passed'] for c in checks)}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(len(checks),'checks; passed:',report['passed']);raise SystemExit(0 if report['passed'] else 1)
