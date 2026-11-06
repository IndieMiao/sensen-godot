"""Independent geometry, real dimensions, UID and proposal audit; no GPU required."""
from pathlib import Path
import hashlib,json,re,sys
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/alcatraz-ruins-424';KIT=ROOT/'assets/landmarks/alcatraz_island'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
def main():
 stats=json.loads((HERE/'asset_stats.json').read_text());proposal=json.loads((HERE/'suggested_placements.json').read_text());checks=[];assets={};uids=[]
 def check(ok,text):
  checks.append(dict(check=text,passed=bool(ok)))
  if not ok:print('FAIL',text)
 for name,e in stats['assets'].items():
  p=KIT/(name+'.glb');doc,data=load_glb(p);mesh=doc['meshes'][0];primitive=mesh['primitives'][0]
  check(len(doc['meshes'])==1 and len(mesh['primitives'])==1,name+': single mesh and surface')
  check(mesh['name']==name+'_mobile',name+': mobile mesh name')
  check(len(doc['materials'])==1 and not doc.get('images') and not doc.get('skins') and not doc.get('animations'),name+': no textures, skeletons or animations')
  check(set(primitive['attributes'])=={'POSITION','NORMAL','COLOR_0'},name+': vertex-painted only')
  xyz=np.array(accessor(doc,data,primitive['attributes']['POSITION']));normals=np.array(accessor(doc,data,primitive['attributes']['NORMAL']));colors=np.array(accessor(doc,data,primitive['attributes']['COLOR_0']));indices=np.array(accessor(doc,data,primitive['indices'])).reshape(-1,3)
  a,b,c=(xyz[indices[:,j]] for j in range(3));cross=np.cross(b-a,c-a)
  check(np.all(np.linalg.norm(cross,axis=1)>1e-10),name+': no degenerate triangles')
  check(np.all(np.sum(cross*normals[indices].mean(axis=1),axis=1)>-1e-9),name+': normals match winding')
  check(len(indices)==e['triangles'] and len(indices)<=e['triangle_limit'],name+': exported triangle budget')
  lo,hi=xyz.min(axis=0),xyz.max(axis=0)
  check(np.allclose([lo,hi],e['bounds'],atol=1e-6),name+': measured AABB matches spec')
  check(abs(lo[1])<1e-6 and abs(lo[0]+hi[0])<2e-6 and (name=='alc_ruin_vine' or abs(lo[2]+hi[2])<2e-6),name+': local bottom-centre origin')
  check(all(np.allclose(n.get('translation',[0,0,0]),[0,0,0]) and np.allclose(n.get('scale',[1,1,1]),[1,1,1]) for n in doc['nodes']),name+': no baked world position or scale')
  mat=doc['materials'][0]['pbrMetallicRoughness'];check(abs(mat['roughnessFactor']-.9)<1e-6 and mat['metallicFactor']==0,name+': matte material')
  check(np.all(np.isfinite(colors)) and np.all(colors>=0) and np.all(colors<=1),name+': bounded vertex colours')
  if name=='alc_ruin_rubble':check(hi[1]<=.15,name+': flat single-layer rubble <=0.15m')
  if name=='alc_ruin_arch':check(hi[1]<.9 and hi[0]-lo[0]>2,name+': low fallen arch fragment, not an upright doorway')
  if name=='alc_ruin_vine':check(abs(lo[2])<1e-6 and hi[2]<.10,name+': wall-back plane zero and shallow opaque leaves')
  imp=(KIT/(name+'.glb.import')).read_text();uid=re.search(r'uid="(uid://[^"]+)"',imp)
  check(uid is not None and 'gltf/texture_map_mode=1' in imp and 'meshes/light_baking=1' in imp,name+': Godot UID / import contract')
  if uid:uids.append(uid.group(1))
  digest=hashlib.sha256(p.read_bytes()).hexdigest();check(digest==e['sha256'],name+': source manifest matches final export')
  assets[name]=dict(triangles=len(indices),bounds=[lo.tolist(),hi.tolist()],surfaces=1,sha256=digest,uid=uid.group(1) if uid else None)
 check(len(set(uids))==len(uids)==5,'five distinct UIDs')
 check(json.loads((KIT/'ruin_details_manifest.json').read_text())==stats,'runtime and source manifests agree')
 origin=np.array(proposal['ruins_000']['position'])
 check(proposal['ruins_000']['name']=='ruins_000' and np.allclose(origin,[18.5,3.25,5]),'pinned v6 ruins installation unchanged')
 check(all(np.allclose(np.array(p['position'])-origin,p['relative_to_ruins_000']) for p in proposal['instances']),'relative and world coordinates agree')
 check(all(p['asset'] in assets and p['multimesh'] and not p['collision'] and p['scale']==[1,1,1] for p in proposal['instances']),'13 original-scale noninteractive suggestions')
 check(all(abs(p['position'][2]-5.245)<1e-6 for p in proposal['instances'] if p['asset']=='alc_ruin_vine'),'vine back planes 20mm in front of original wall faces')
 stage=json.loads((QA/'stage.json').read_text())
 for path,digest in stage['unchanged_files'].items():check(hashlib.sha256((QA/'project'/path).read_bytes()).hexdigest()==digest,'v6 original remains byte-identical: '+path)
 check(not (KIT/'layout.json').exists(),'proposal does not overwrite Marco Polo layout')
 report={'passed':all(c['passed'] for c in checks),'checks':checks,'assets':assets,'unique_triangles':sum(a['triangles'] for a in assets.values()),'instances':len(proposal['instances']),'placed_triangles':sum(assets[p['asset']]['triangles'] for p in proposal['instances'])}
 (QA/'asset-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('RUINS_VERIFY',report['passed'],len(checks),'checks, triangles',report['unique_triangles'],'placed',report['placed_triangles'])
 raise SystemExit(not report['passed'])
if __name__=='__main__':main()
