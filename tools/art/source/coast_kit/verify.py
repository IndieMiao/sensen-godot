"""Audit exported geometry and every ordered out->in mating combination."""
from pathlib import Path
import argparse,hashlib,json,math,re,subprocess,sys
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];KIT=ROOT/'assets/landmarks/_shared/coast_kit';QA=ROOT/'output/coast-kit'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
parser=argparse.ArgumentParser();parser.add_argument('--geometry-only',action='store_true');args=parser.parse_args()
manifest=json.loads((KIT/'manifest.json').read_text());report={'author':'赵云','checks':[],'assets':{},'mates':[]};geometry={};uids=[]
def check(ok,label):
    report['checks'].append({'check':label,'passed':bool(ok)})
    if not ok:print('FAIL',label)
def signature(points):return {tuple(round(float(v),5) for v in p) for p in points}
def yaw(a):return np.array([[math.cos(a),0,math.sin(a)],[0,1,0],[-math.sin(a),0,math.cos(a)]])

for name,e in manifest['assets'].items():
    path=KIT/(name+'.glb');doc,blob=load_glb(path);mesh=doc['meshes'][0];p=mesh['primitives'][0]
    check(len(doc['meshes'])==1 and len(mesh['primitives'])==1 and mesh['name']==name+'_mobile',name+': one mobile mesh / surface')
    check(len(doc['nodes'])==1 and doc['nodes'][0]=={'mesh':0,'name':name},name+': identity construction root')
    check(not any(doc.get(k) for k in ['skins','animations','textures','images']),name+': no textures / skin / animation')
    check(len(doc['materials'])==1 and set(p['attributes'])=={'POSITION','NORMAL','COLOR_0'},name+': one vertex-colour material')
    xyz=np.array(accessor(doc,blob,p['attributes']['POSITION']));normals=np.array(accessor(doc,blob,p['attributes']['NORMAL']));colors=np.array(accessor(doc,blob,p['attributes']['COLOR_0']));ids=np.array(accessor(doc,blob,p['indices'])).reshape(-1,3)
    geometry[name]=xyz;tri=len(ids);lo,hi=xyz.min(0),xyz.max(0)
    check(tri==e['triangles'] and tri<=400,name+': measured triangle budget')
    check(abs(lo[1])<1e-6 and np.allclose([lo,hi],e['bounds'],atol=1.1e-6),name+': grounded / manifest bounds')
    check(np.isfinite(xyz).all() and np.isfinite(normals).all() and np.isfinite(colors).all() and (colors>=0).all() and (colors<=1).all(),name+': finite geometry / bounded colours')
    face=np.cross(xyz[ids[:,1]]-xyz[ids[:,0]],xyz[ids[:,2]]-xyz[ids[:,0]])
    lengths=np.linalg.norm(face,axis=1);agreement=np.sum(face*normals[ids].mean(1),axis=1)
    check((lengths>1e-9).all() and (agreement>0).all(),name+': no degenerate or reversed shading triangles')
    mat=doc['materials'][0]['pbrMetallicRoughness'];check(abs(mat['roughnessFactor']-.94)<1e-6 and mat['metallicFactor']==0,name+': matte material')
    digest=hashlib.sha256(path.read_bytes()).hexdigest();check(digest==e['sha256'],name+': manifest matches actual export')
    for port in e['ports']:
        if 'profile' not in port:continue
        at=np.array(port['position']);normal=np.array(port['outward']);points=xyz[np.abs((xyz-at)@normal)<1e-6]
        check(signature(points)==signature(port['profile']),name+'/'+port['name']+': full exported seam matches declared profile')
    uid=None
    if not args.geometry_only:
        text=(KIT/(name+'.glb.import')).read_text();match=re.search(r'^uid="(uid://[^"]+)"$',text,re.M);uid=match.group(1) if match else None
        check(uid is not None and all(s in text.splitlines() for s in ['nodes/root_script=null','gltf/texture_map_mode=1','meshes/light_baking=1','meshes/generate_lods=false']),name+': Godot UID / complete stable import defaults')
        uids.append(uid)
    report['assets'][name]={'triangles':tri,'surfaces':1,'sha256':digest,'uid':uid,'bounds':[lo.tolist(),hi.tolist()]}

for an,ae in manifest['assets'].items():
    for ap in ae['ports']:
        if ap['name']!='out' or 'profile' not in ap:continue
        for bn,be in manifest['assets'].items():
            for bp in be['ports']:
                if bp['name']!='in' or 'profile' not in bp or bp['family']!=ap['family']:continue
                na,nb=np.array(ap['outward']),np.array(bp['outward'])
                angle=math.atan2(nb[2],nb[0])-math.atan2(-na[2],-na[0]);r=yaw(angle);t=np.array(ap['position'])-r@np.array(bp['position'])
                a=np.array(ap['profile']);b=np.array(bp['profile'])@r.T+t
                # Symmetric maximum closest-vertex gap of the actual profile sets.
                distance=np.linalg.norm(a[:,None]-b[None,:],axis=2)
                gap=max(float(distance.min(0).max()),float(distance.min(1).max()))
                check(gap<1e-6 and np.allclose(r@nb,-na),an+' -> '+bn+': no positive seam gap')
                report['mates'].append({'from':an,'to':bn,'yaw_degrees':round(math.degrees(angle),6),'max_profile_gap_m':gap})
check(len(report['mates'])==43,'36 mixed-height rock, 1 wall and 6 dock mating combinations covered')
for name in ['coast_dock_straight','coast_dock_bollard']:
    edge=np.array([[1,1.2,-1],[1,1.2,1]])
    landing=np.array([[-1,1.2,-1],[1,1.2,-1]])
    transformed=landing@yaw(math.pi/2).T+np.array([2,0,0])
    exists=all(np.linalg.norm(geometry['coast_water_steps']-p,axis=1).min()<1e-6 for p in landing)
    check(exists and signature(edge)==signature(transformed),name+' -> stairs: 2m walking edge at identical height')
check(len(manifest['assets'])==15 and not manifest['example_layout_included'],'15 independent prototypes; no delivered example layout')
check(not any(KIT.glob('*layout*')),'no runtime example layout file')
if not args.geometry_only:check(len(set(uids))==15,'15 distinct Godot-generated UIDs')
check(json.loads((HERE/'asset_stats.json').read_text())==manifest,'runtime and source manifests agree')
unchanged=subprocess.check_output(['git','diff','HEAD','--name-only','--','assets/landmarks/alcatraz_island'],cwd=ROOT,text=True)
check(not unchanged,'all Alcatraz files unchanged in the worktree')
for e in manifest['assets'].values():
    if 'reuse' in e:check(hashlib.sha256((ROOT/e['reuse']['source_file']).read_bytes()).hexdigest()==e['reuse']['source_sha256'],'reused Alcatraz rock source hash retained')
report['unique_triangles']=sum(e['triangles'] for e in report['assets'].values());report['passed']=all(c['passed'] for c in report['checks'])
(QA/('geometry-preimport.json' if args.geometry_only else 'asset-validation.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('COAST_VERIFY',report['passed'],len(report['checks']),'checks;',len(report['mates']),'mating pairs;',report['unique_triangles'],'unique triangles')
raise SystemExit(0 if report['passed'] else 1)
