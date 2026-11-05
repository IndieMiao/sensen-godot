"""Measure the seven exported meshes, actual colours, pivots and LOD ratios."""
from pathlib import Path
import hashlib,json,re,sys
import numpy as np
ROOT=Path(__file__).resolve().parents[4];KIT=ROOT/'assets/landmarks/alcatraz_island';OUT=ROOT/'output/alcatraz-far-424'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
def main():
 m=json.loads((KIT/'alc_far_manifest.json').read_text());checks=[];measured={};uids=[]
 def check(v,label):checks.append({'check':label,'passed':bool(v)})
 for name,spec in m['assets'].items():
  path=KIT/spec['file'];d,b=load_glb(path);prims=d['meshes'][0]['primitives']
  check(len(d['meshes'])==1 and d['meshes'][0]['name']==name+'_mobile',name+' one named mesh')
  check(len(prims)==1 and len(d['materials'])==1,name+' one surface/material')
  p=prims[0];a=p['attributes'];v=np.array(accessor(d,b,a['POSITION']));n=np.array(accessor(d,b,a['NORMAL']));c=np.array(accessor(d,b,a['COLOR_0']));idx=np.array(accessor(d,b,p['indices'])).reshape(-1,3)
  check(set(a)=={'POSITION','NORMAL','COLOR_0'},name+' vertex colours without UV or skin')
  check(not d.get('images') and not d.get('textures') and not d.get('animations') and not d.get('skins'),name+' no textures, skeleton or animation')
  check(np.isfinite(v).all() and np.allclose(np.linalg.norm(n,axis=1),1,atol=.0001),name+' finite vertices / normals')
  t=v[idx];area=np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1)
  check((area>1e-10).all(),name+' no zero-area triangles')
  low=v.min(0);high=v.max(0)
  check(abs(low[1])<1e-5 and np.allclose((low+high)[[0,2]],0,atol=1e-5),name+' bottom / footprint-centre origin')
  check(len(idx)==spec['triangles'] and np.allclose([low,high],spec['bounds'],atol=1e-5),name+' measured manifest')
  check(c.min()>=0 and c.max()<=1 and np.allclose(c[:,3],1),name+' opaque vertex colours')
  if spec.get('height_m'):check(abs(high[1]-spec['height_m'])<1e-5,name+' real target height')
  cfg=(KIT/(spec['file']+'.import')).read_text();uid=re.search(r'uid="(uid://[a-y0-8]+)"',cfg)
  check(uid is not None,name+' Godot-generated UID');uids.append(uid.group(1) if uid else None)
  check('gltf/texture_map_mode=1' in cfg and 'alc_far_material_import.gd' in cfg,name+' import/material contract')
  check(hashlib.sha256(path.read_bytes()).hexdigest()==spec['sha256'],name+' SHA-256')
  for node in d['nodes']:
   if 'mesh' in node:check(node.get('translation',[0,0,0])==[0,0,0] and node.get('scale',[1,1,1])==[1,1,1] and node.get('rotation',[0,0,0,1])==[0,0,0,1],name+' unit node transform')
  measured[name]={'triangles':len(idx),'dimensions_m':(high-low).tolist(),'bounds':[low.tolist(),high.tolist()]}
 check(len(set(uids))==len(uids),'Unique import UIDs')
 for name in ['alc_lighthouse','alc_watertower']:
  ratio=measured[name+'_far']['triangles']/measured[name]['triangles'];check(.18<=ratio<=.30,name+' far/near ratio approx quarter')
  check(np.allclose(measured[name]['bounds'],measured[name+'_far']['bounds'],atol=1e-5),name+' near/far same pivot and overall bounds')
 total=sum(s['triangles'] for s in measured.values());check(total<=40000,'Seven assets total <=40000')
 result={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','checks':checks,'measured':measured,'total_triangles':total,'surfaces':len(measured),'passed':all(c['passed'] for c in checks)}
 (OUT/'geometry-validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print('Checks',len(checks),'passed',result['passed'],'triangles',total)
 for c in checks:
  if not c['passed']:print('FAIL',c['check'])
 if not result['passed']:sys.exit(1)
if __name__=='__main__':main()
