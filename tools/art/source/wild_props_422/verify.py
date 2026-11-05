"""Read the exported binary, not Blender statistics. No GPU or Godot execution."""
from pathlib import Path
import hashlib,json,math,re,subprocess,sys
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];QA=ROOT/'output/wild-422';ART=ROOT/'assets/farm/art'
sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
BASE='93befb18cd5af7e30a966d2c112279287b71b3e2'
def main():
 spec=json.loads((HERE/'asset_stats.json').read_text());checks=[];assets={};uids=[]
 def check(ok,label):
  checks.append(dict(check=label,passed=bool(ok)))
  if not ok:print('FAIL',label)
 for name,entry in spec['assets'].items():
  path=ART/(name+'.glb');doc,data=load_glb(path)
  check(len(doc.get('meshes',[]))==1 and len(doc['meshes'][0]['primitives'])==1,name+': one mesh, one surface')
  check(doc['meshes'][0]['name']==name+'_mobile',name+': mobile mesh name')
  check(len(doc['materials'])==1 and not doc.get('images') and not doc.get('textures') and not doc.get('skins') and not doc.get('animations'),name+': matte untextured/static asset')
  mat=doc['materials'][0]['pbrMetallicRoughness']
  check(abs(mat['roughnessFactor']-.9)<1e-6 and mat.get('metallicFactor',1)==0,name+': matte roughness .9 / metallic 0')
  p=doc['meshes'][0]['primitives'][0]
  check(set(p['attributes'])=={'POSITION','NORMAL','COLOR_0'},name+': opaque vertex-painted geometry only')
  positions=np.array(accessor(doc,data,p['attributes']['POSITION']));normals=np.array(accessor(doc,data,p['attributes']['NORMAL']));colors=np.array(accessor(doc,data,p['attributes']['COLOR_0']))
  indices=np.array(accessor(doc,data,p['indices'])).reshape(-1,3);count=len(indices)
  check(count==entry['triangles'] and count<=300,name+': actual triangle count <=300')
  a,b,c=(positions[indices[:,i]] for i in range(3));cross=np.cross(b-a,c-a)
  check(np.all(np.linalg.norm(cross,axis=1)>1e-10),name+': no degenerate triangles')
  check(np.all(np.sum(cross*normals[indices].mean(axis=1),axis=1)>-1e-9),name+': winding/normals consistent')
  lo=positions.min(axis=0);hi=positions.max(axis=0)
  check(np.allclose([lo,hi],entry['bounds'],atol=1e-6),name+': bounds match manifest')
  check(abs(lo[1])<1e-6 and abs(lo[0]+hi[0])<2e-6 and abs(lo[2]+hi[2])<2e-6,name+': bottom-centre origin')
  check(all('matrix' not in n and np.allclose(n.get('scale',[1,1,1]),[1,1,1]) and np.allclose(n.get('translation',[0,0,0]),[0,0,0]) for n in doc['nodes']),name+': identity node transforms')
  check(np.all(colors>=0) and np.all(colors<=1) and (colors.shape[1]==3 or np.allclose(colors[:,3],1)),name+': finite opaque vertex colours')
  if name.startswith('wild_pebbles'):check(hi[1]<=.15,name+': stones <=0.15m high')
  if name.startswith('wild_flower'):check(hi[1]<.36 and hi[0]-lo[0]<.50,name+': shorter/smaller than 0.65m flax resource')
  if name=='wild_cattail_water':
   brown=(colors[:,0]>colors[:,1]*1.2)&(colors[:,0]>colors[:,2]*1.5)
   check(positions[brown,1].min()>.40 and hi[0]-lo[0]<.5,name+': brown only on upper seed heads, no soil base')
  imp=(ART/(name+'.glb.import')).read_text();uid=re.search(r'uid="(uid://[^"]+)"',imp)
  check(uid is not None and 'gltf/texture_map_mode=1' in imp and 'meshes/light_baking=1' in imp,name+': actual import UID, texture_map_mode/light_baking 1')
  if uid:uids.append(uid.group(1))
  digest=hashlib.sha256(path.read_bytes()).hexdigest();check(digest==entry['sha256'],name+': export SHA matches source manifest')
  assets[name]=dict(triangles=count,surfaces=1,bounds=[lo.tolist(),hi.tolist()],uid=uid.group(1) if uid else None,sha256=digest)
 check(len(uids)==len(set(uids))==len(assets),'all assets have distinct Godot-generated UIDs')
 manifest=json.loads((ART/'manifest.json').read_text());original=json.loads(subprocess.check_output(['git','show',BASE+':assets/farm/art/manifest.json'],cwd=ROOT,text=True))
 check({k:v for k,v in manifest['assets'].items() if k not in assets}==original['assets'],'all previous manifest values preserved')
 check(list(manifest['assets'])==list(original['assets'])+list(assets),'manifest only appends this kit in order')
 old=json.loads(subprocess.check_output(['git','show','c040a643:tools/art/source/wild_props_422/asset_stats.json'],cwd=ROOT,text=True))
 check(all(spec['assets'][name]==entry for name,entry in old['assets'].items()),'original twelve asset entries unchanged')
 check(all((ART/(name+suffix)).read_bytes()==subprocess.check_output(['git','show','c040a643:assets/farm/art/'+name+suffix],cwd=ROOT) for name in old['assets'] for suffix in ['.glb','.glb.import']),'original twelve GLBs and import files byte-identical')
 check(all(manifest['assets'][name]==entry for name,entry in spec['assets'].items()),'source metadata and runtime manifest agree')
 result=dict(passed=all(x['passed'] for x in checks),checks=checks,assets=assets,total_unique_triangles=sum(a['triangles'] for a in assets.values()),base_commit=BASE)
 (QA/'asset-validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print('WILD_VERIFY',result['passed'],len(checks),'checks',result['total_unique_triangles'],'unique triangles')
 raise SystemExit(not result['passed'])
if __name__=='__main__':main()
