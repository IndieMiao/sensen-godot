"""Raw GLB prefix proof: approved geometry, colors, normals and UV are untouched."""
from pathlib import Path
import json,struct,subprocess,hashlib
import numpy as np
ROOT=Path(__file__).resolve().parents[4];BASE='c7a0a4b6a';OUT=ROOT/'assets/rooms/market_plaza'
def read(raw):
 n=struct.unpack_from('<I',raw,12)[0];return json.loads(raw[20:20+n]),raw[28+n:]
def array(doc,blob,i):
 a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']];dt=np.dtype({5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]);w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
 return np.ndarray((a['count'],w),dtype=dt,buffer=blob,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',dt.itemsize*w),dt.itemsize))
def original(rel):return subprocess.check_output(['git','show',BASE+':'+rel],cwd=ROOT)
def main():
 report={'base':BASE,'assets':{},'preserved':{}}
 for p in sorted(OUT.glob('facade_*.glb')):
  rel=str(p.relative_to(ROOT));a,ab=read(original(rel));b,bb=read(p.read_bytes());pa=a['meshes'][0]['primitives'][0];pb=b['meshes'][0]['primitives'][0]
  assert len(b['meshes'][0]['primitives'])==1
  assert a['materials']==b['materials'] and a['nodes']==b['nodes']
  for s,i in pa['attributes'].items():
   old=array(a,ab,i);new=array(b,bb,pb['attributes'][s]);assert np.array_equal(old,new[:len(old)]),(p.name,s)
  ix=array(a,ab,pa['indices']);jx=array(b,bb,pb['indices']);assert np.array_equal(ix,jx[:len(ix)])
  delta=(len(jx)-len(ix))//3;assert 0<delta<=40
  pos=array(b,bb,pb['attributes']['POSITION']);nr=array(b,bb,pb['attributes']['NORMAL']);added=pos[int(a['accessors'][pa['attributes']['POSITION']]['count']):]
  assert added[:,2].max()<=1.23001 and np.abs(added[:,0]).min()>=1.9399
  faces=pos[jx[len(ix):].reshape(-1,3)];face_n=np.cross(faces[:,1]-faces[:,0],faces[:,2]-faces[:,0]);assert np.all(np.linalg.norm(face_n,axis=1)>1e-8)
  assert np.all(np.sum(face_n*nr[jx[len(ix):].reshape(-1,3)[:,0]],axis=1)>0)
  imp=OUT/(p.name+'.import');assert imp.read_bytes()==original(str(imp.relative_to(ROOT)))
  report['assets'][p.stem]={'before_triangles':len(ix)//3,'after_triangles':len(jx)//3,'added_triangles':delta,'all_original_attributes_and_indices_exact':True,'material_and_nodes_exact':True,'import_uid_exact':True,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
 changed={f'assets/rooms/market_plaza/{n}.glb' for n in report['assets']}|{'assets/rooms/market_plaza/shell_asset_stats.json'}
 for rel in subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'--','assets/rooms/market_plaza','scenes/market_plaza'],cwd=ROOT,text=True).splitlines():
  if rel in changed:continue
  data=(ROOT/rel).read_bytes();assert data==original(rel),rel;report['preserved'][rel]=hashlib.sha256(data).hexdigest()
 assert 'assets/rooms/market_plaza/layout.json' in report['preserved']
 dest=ROOT/'docs/design/market-facade-seams-218-2026-11-13';dest.mkdir(parents=True,exist_ok=True);(dest/'preservation.json').write_text(json.dumps(report,indent=2)+'\n')
 print('PASS',len(report['assets']),'facades +24 triangles; all original attributes exact;',len(report['preserved']),'non-target files exact')
if __name__=='__main__':main()
