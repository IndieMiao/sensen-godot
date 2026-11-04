"""Independent GLB geometry/material/UID and original-footprint contract checks."""
from pathlib import Path
import configparser,hashlib,json,re,subprocess,sys
import numpy as np
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/farm/art';OUT=ROOT/'output/gathered-417'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
manifest=json.loads((KIT/'manifest.json').read_text());stats=json.loads((SRC/'asset_stats.json').read_text())
originals=json.loads((SRC/'original_metrics.json').read_text());snapshot=json.loads((OUT/'runtime-base.json').read_text())
uids=json.loads((OUT/'uid-generation.json').read_text())['uids'];checks=[];measured={}
def check(ok,label):
    checks.append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)
def linear(h):
    c=np.array(list(bytes.fromhex(h)))/255
    return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
ref,_=load_glb(KIT/'sign.glb');ref_cfg=configparser.ConfigParser(interpolation=None);ref_cfg.read(KIT/'sign.glb.import')
def params(cfg):return {k:v for k,v in cfg['params'].items() if v!='null'}
seen=set();expected_sprouts={'grove','reed_bank','hardwood_grove','flax_patch'}
for name,art in stats.items():
    full=name+'_gathered';path=KIT/(full+'.glb');doc,data=load_glb(path);spec=manifest['assets'][full]
    check(len(doc['meshes'])==1 and doc['meshes'][0]['name']==full+'_mobile',full+': one named mobile mesh')
    prims=doc['meshes'][0]['primitives'];check(len(prims)==1,full+': one surface')
    p=prims[0];a=p['attributes'];points=np.array(accessor(doc,data,a['POSITION']));normals=np.array(accessor(doc,data,a['NORMAL']))
    colors=np.array(accessor(doc,data,a['COLOR_0']));indices=np.array(accessor(doc,data,p['indices'])).reshape(-1,3)
    lo=points.min(axis=0);hi=points.max(axis=0);old=np.array(originals[name]['bounds'])
    check(len(indices)==spec['triangles']<=600,full+': actual triangle budget <=600')
    check(np.allclose([lo,hi],spec['bounds'],atol=1e-6),full+': manifest bounds match actual vertices')
    check(all(lo[i]>=old[0,i]-1e-5 and hi[i]<=old[1,i]+1e-5 for i in [0,2]),full+': inside original X/Z footprint at unchanged origin')
    check(hi[1]<old[1,1] and abs(lo[1])<1e-6,full+': lower than original and grounded at Y=0')
    check(all(n.get('translation',[0,0,0])==[0,0,0] and n.get('scale',[1,1,1])==[1,1,1] and n.get('rotation',[0,0,0,1])==[0,0,0,1] for n in doc['nodes']),full+': zero translation, unit scale and rotation')
    check(not doc.get('animations') and not doc.get('skins') and not doc.get('cameras') and 'KHR_lights_punctual' not in doc.get('extensions',{}),full+': no animation, bones, camera or light')
    check(set(a)=={'POSITION','NORMAL','COLOR_0'} and not doc.get('textures') and not doc.get('images'),full+': vertex colours only, no textures')
    check(doc['materials']==ref['materials'],full+': exact sign.glb matte material payload')
    check(np.isfinite(points).all() and np.allclose(np.linalg.norm(normals,axis=1),1,atol=1e-5),full+': finite positions and unit normals')
    area=np.linalg.norm(np.cross(points[indices[:,1]]-points[indices[:,0]],points[indices[:,2]]-points[indices[:,0]]),axis=1)
    check(np.all(area>1e-10) and np.allclose(colors[:,3],1),full+': no degenerate triangles, opaque paint')
    proxy=np.array(art['visibility_vertices'])
    check(np.max(np.min(np.linalg.norm(proxy[:,None]-points[None,:],axis=2),axis=1))<2e-6,full+': visibility patch consists of real exported vertices')
    cfg=configparser.ConfigParser(interpolation=None);cfg.read(KIT/(full+'.glb.import'));uid=cfg['remap']['uid'].strip('"')
    check(params(cfg)==params(ref_cfg),full+': sign import params including tangents/LOD/light_baking=1')
    check(re.fullmatch(r'uid://[a-y0-8]+',uid)!=None and uid==uids[name] and uid not in seen,full+': unique Godot-generated UID, valid alphabet');seen.add(uid)
    check(hashlib.sha256(path.read_bytes()).hexdigest()==spec['sha256'],full+': manifest SHA-256')
    check((OUT/'project/assets/farm/art'/path.name).read_bytes()==path.read_bytes(),full+': exact delivered model rendered')
    sprout_color=np.max(abs(colors[:,:3]-linear('8FA46B')),axis=1)<4e-5
    check(len(spec['regrowth_sprouts'])==(2 if name in expected_sprouts else 0) and bool(sprout_color.any())==(name in expected_sprouts),full+': shared regrowth only on the four approved plant kinds')
    if name=='grove':check(hi[1]<=originals[name]['bounds'][1][1]*.5 and len(spec['cut_tree_roots'])==2,'Grove: clearly small tree, two pale stumps')
    if name=='rock_pile':check(abs(hi[1]-.15)<1e-6 and spec['pebble_count']==4,'Rock: .15m-high broad flat stone and four pebbles')
    if name=='reed_bank':check(abs(hi[1]-.33)<1e-6 and not any('Cattail' in s for s in spec['source_parts_triangles']),'Reed: one-third-height cuts and no cattails')
    if name=='clay_pit':check(hi[1]<.13 and not any('block' in s.lower() or 'mound' in s.lower() for s in spec['source_parts_triangles']),'Clay: empty, low pit and flat spade; no mound or bricks')
    if name=='herb_patch':
        leaf=np.max(abs(colors[:,:3]-linear('B8CCA3')),axis=1)<4e-5
        check(np.ptp(points[leaf,0])>=originals[name]['dimensions_xyz'][0]*.5,'Herb: remaining pale leaf clump at least half original width')
    if name=='hardwood_grove':check(not any('canopy' in s.lower() or 'billet' in s.lower() for s in spec['source_parts_triangles']),'Hardwood: no crown or lumber')
    if name=='flax_patch':
        blue=np.min([np.max(abs(colors[:,:3]-linear(h)),axis=1) for h in ['85ACE6','A0C3EE','6E98D7']],axis=0)<4e-5
        check(not blue.any() and spec['stubble_count']==16,'Flax: original stem centres, no blue flower paint')
    measured[name]={'triangles':len(indices),'surfaces':len(prims),'bounds':[lo.tolist(),hi.tolist()],'uid':uid,'sha256':spec['sha256']}
baseline=json.loads(subprocess.check_output(['git','show',snapshot['art_base']+':assets/farm/art/manifest.json'],cwd=ROOT))
old=json.loads(json.dumps(manifest))
for name in stats:del old['assets'][name+'_gathered']
check(old==baseline,'Manifest appends seven gathered entries; every original entry preserved')
allowed={'assets/farm/art/manifest.json'}|{'assets/farm/art/'+n+'_gathered'+s for n in stats for s in ['.glb','.glb.import']}
changed=set(subprocess.check_output(['git','diff','--name-only',snapshot['art_base'],'--','assets/farm/art'],cwd=ROOT,text=True).splitlines())
check(changed<=allowed,'All original runtime art and imports unchanged')
for path,digest in snapshot['files'].items():check(hashlib.sha256((OUT/'project'/path).read_bytes()).hexdigest()==digest,'Native b1 unchanged: '+path)
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','checks':checks,'assets':measured,
    'runtime':snapshot,'passed':all(c['passed'] for c in checks)}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('GATHERED_GEOMETRY',report['passed'],len(checks));raise SystemExit(0 if report['passed'] else 1)
