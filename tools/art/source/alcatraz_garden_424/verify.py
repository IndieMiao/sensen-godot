"""Independent geometry, real dimensions, UID and proposal audit; no GPU required."""
from pathlib import Path
import hashlib,json,re,sys
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/alcatraz-garden-424';KIT=ROOT/'assets/landmarks/alcatraz_island'
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
  check(abs(lo[1])<1e-6 and abs(lo[0]+hi[0])<2e-6 and abs(lo[2]+hi[2])<2e-6,name+': local bottom-centre origin')
  check(all(np.allclose(n.get('translation',[0,0,0]),[0,0,0]) and np.allclose(n.get('scale',[1,1,1]),[1,1,1]) for n in doc['nodes']),name+': no baked world position or scale')
  mat=doc['materials'][0]['pbrMetallicRoughness'];check(abs(mat['roughnessFactor']-.9)<1e-6 and mat['metallicFactor']==0,name+': matte material')
  check(np.all(np.isfinite(colors)) and np.all(colors>=0) and np.all(colors<=1),name+': bounded vertex colours')
  if name=='alc_hedge':
   check(np.allclose([lo[0],hi[0]],[-.5,.5],atol=1e-6),name+': exactly 1m on X')
   ends=[set(tuple(np.round(p[1:],6)) for p in xyz[np.abs(xyz[:,0]-x)<1e-6]) for x in [-.5,.5]]
   check(ends[0]==ends[1],name+': identical end profiles for gapless MultiMesh runs')
  imp=(KIT/(name+'.glb.import')).read_text();uid=re.search(r'uid="(uid://[^"]+)"',imp)
  check(uid is not None and 'gltf/texture_map_mode=1' in imp and 'meshes/light_baking=1' in imp,name+': Godot UID / import contract')
  if uid:uids.append(uid.group(1))
  digest=hashlib.sha256(p.read_bytes()).hexdigest();check(digest==e['sha256'],name+': source manifest matches final export')
  assets[name]=dict(triangles=len(indices),bounds=[lo.tolist(),hi.tolist()],surfaces=1,sha256=digest,uid=uid.group(1) if uid else None)
 check(len(set(uids))==len(uids)==5,'five distinct UIDs')
 check(json.loads((KIT/'garden_manifest.json').read_text())==stats,'runtime and source manifests agree')
 check(len(proposal['groups'])==15 and all(g['added_instances']>0 for g in proposal['groups']),'15 proposed look-points all have flowers/hedge')
 for row in range(1,4):
  stations=[g['walk_station'][0] for g in proposal['groups'] if g['name'].startswith(f'terrace_{row}_')]
  check(max(b-a for a,b in zip(stations,stations[1:]))<=6.500001,f'terrace {row}: station gaps at most 6.5m')
 check(all(p['asset'] in assets and p['multimesh'] and p['collision']==False and p['scale']==[1,1,1] for p in proposal['instances']),'proposal uses only this kit, at original scale, without new collision')
 # New decoration stays on the garden side of the three paved runs.
 check(all(p['position'][2]+max(abs(v[2]) for v in stats['assets'][p['asset']]['bounds'])<({3.25:6,5.5:1.5,7.75:-3}.get(p['position'][1],99)) for p in proposal['instances'] if p['asset']!='alc_planter'),'flower/hedge footprints remain outside the paved path')
 stage=json.loads((QA/'stage.json').read_text())
 for path,digest in stage['unchanged_files'].items():check(hashlib.sha256((QA/'project'/path).read_bytes()).hexdigest()==digest,'v6 original remains byte-identical: '+path)
 check(not (KIT/'layout.json').exists(),'proposal does not overwrite Marco Polo layout')
 report={'passed':all(c['passed'] for c in checks),'checks':checks,'assets':assets,'unique_triangles':sum(a['triangles'] for a in assets.values()),'instances':len(proposal['instances']),'placed_triangles':sum(assets[p['asset']]['triangles'] for p in proposal['instances']),'group_count':len(proposal['groups'])}
 (QA/'asset-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('GARDEN_VERIFY',report['passed'],len(checks),'checks, triangles',report['unique_triangles'],'placed',report['placed_triangles'])
 raise SystemExit(not report['passed'])
if __name__=='__main__':main()
