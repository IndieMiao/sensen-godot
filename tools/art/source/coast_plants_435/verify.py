"""Verify exported geometry, solid foliage, shared LOD pivots and import contract."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];KIT=ROOT/'assets/landmarks/_shared/coast_plants';QA=ROOT/'output/coast-plants'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
parser=argparse.ArgumentParser();parser.add_argument('--geometry-only',action='store_true');args=parser.parse_args()
data=json.loads((KIT/'manifest.json').read_text());report={'checks':[],'assets':{},'author':'赵云'};uids=[]
def check(ok,label):
 report['checks'].append({'passed':bool(ok),'check':label})
 if not ok:print('FAIL',label)
for name,e in data['assets'].items():
 path=KIT/(name+'.glb');doc,blob=load_glb(path);p=doc['meshes'][0]['primitives'][0]
 xyz=np.array(accessor(doc,blob,p['attributes']['POSITION']));normal=np.array(accessor(doc,blob,p['attributes']['NORMAL']));colors=np.array(accessor(doc,blob,p['attributes']['COLOR_0']));ids=np.array(accessor(doc,blob,p['indices'])).reshape(-1,3)
 budget=120 if e['lod']=='far' else 800 if e['lod']=='near' else 400
 check(len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1 and doc['meshes'][0]['name']==name+'_mobile',name+': single mobile mesh / surface')
 check(len(doc['nodes'])==1 and doc['nodes'][0]=={'mesh':0,'name':name},name+': identity node and local root')
 check(len(ids)<=budget and len(ids)==e['triangles'],name+': measured triangles within budget')
 check(not any(doc.get(k) for k in ['skins','animations','textures','images']),name+': no texture / skin / animation')
 check(set(p['attributes'])=={'POSITION','NORMAL','COLOR_0'},name+': vertex paint without texture coordinates')
 check(np.isfinite(xyz).all() and np.isfinite(normal).all() and np.isfinite(colors).all(),name+': finite vertex attributes')
 check(np.allclose(np.linalg.norm(normal,axis=1),1,atol=1e-4),name+': normalized normals')
 check(np.all(colors>=-1e-6) and np.all(colors<=1.000001) and (colors.shape[1]==3 or np.allclose(colors[:,3],1)),name+': opaque bounded vertex colours')
 mat=doc['materials'][0];pbr=mat['pbrMetallicRoughness']
 check(len(doc['materials'])==1 and mat.get('alphaMode','OPAQUE')=='OPAQUE' and not mat.get('doubleSided',False) and pbr['metallicFactor']==0 and abs(pbr['roughnessFactor']-.9)<1e-6,name+': single opaque matte material, culled solid geometry')
 lo=xyz.min(0);hi=xyz.max(0)
 check(np.allclose([lo,hi],e['bounds'],atol=1e-6) and abs(lo[1])<1e-6,name+': grounded and manifest bounds match')
 if e['lod']=='single':check(np.allclose((lo+hi)[[0,2]],0,atol=1e-6),name+': footprint-centred scatter pivot')
 face=np.cross(xyz[ids[:,1]]-xyz[ids[:,0]],xyz[ids[:,2]]-xyz[ids[:,0]]);areas=np.linalg.norm(face,axis=1);dots=np.sum(face*normal[ids].mean(1),axis=1)
 check(np.all(areas>1e-10),name+': no zero-area triangles')
 check(np.all(dots>0),name+': outward geometric / shading normal agreement')
 # Weld by position for the closed-surface edge check; colour/normal splits are intentional.
 keys=[tuple(np.round(v,6)) for v in xyz];edges={}
 for a,b,c in ids:
  for v,w in [(a,b),(b,c),(c,a)]:
   key=tuple(sorted([keys[v],keys[w]]));edges[key]=edges.get(key,0)+1
 check(all(n%2==0 for n in edges.values()),name+': no open edges, leaves and canopy have undersides')
 sha=hashlib.sha256(path.read_bytes()).hexdigest();check(sha==e['sha256'],name+': exported SHA matches manifest')
 uid=None
 if not args.geometry_only:
  s=(KIT/(name+'.glb.import')).read_text();m=re.search(r'^uid="(uid://[^"]+)"$',s,re.M);uid=m.group(1) if m else None;uids.append(uid)
  check(uid is not None and all(x in s.splitlines() for x in ['nodes/root_script=null','gltf/texture_map_mode=1','meshes/light_baking=1','meshes/generate_lods=false']),name+': generated UID and stable import settings')
 report['assets'][name]={'triangles':len(ids),'budget':budget,'surface_count':1,'sha256':sha,'bounds':[lo.tolist(),hi.tolist()],'uid':uid,'reversed_faces':int((dots<=0).sum()),'open_edges':sum(n%2!=0 for n in edges.values())}
for group in data['lod_groups']:
 near=report['assets'][group['near']];far=report['assets'][group['far']]
 check(np.allclose(near['bounds'],far['bounds'],atol=1e-5),group['near']+': near/far shared envelope and origin')
 check(group['switch_distance_m']==40 and group['margin_m']==0,group['near']+': 40m switch contract')
check(len(data['assets'])==10 and len(data['lod_groups'])==2,'six ground prototypes plus two near/far tree pairs')
check(not any(KIT.glob('*layout*')) and not data['example_layout_included'],'no delivered example layout')
check(json.loads((HERE/'asset_stats.json').read_text())==data,'source and runtime stats match')
if not args.geometry_only:check(len(set(uids))==10,'ten distinct Godot-generated UIDs')
changed=subprocess.check_output(['git','diff','--name-only','--diff-filter=MDRCT','7214c718','--'],cwd=ROOT,text=True).splitlines()
check(not changed,'all previously tracked files preserved')
report['triangles_total']=sum(a['triangles'] for a in report['assets'].values());report['passed']=all(c['passed'] for c in report['checks'])
(QA/('geometry-preimport.json' if args.geometry_only else 'asset-validation.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('COAST_PLANTS_VERIFY',report['passed'],len(report['checks']),'checks;',report['triangles_total'],'triangles')
raise SystemExit(0 if report['passed'] else 1)
