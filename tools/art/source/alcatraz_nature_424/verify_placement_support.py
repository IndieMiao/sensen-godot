"""Check plant roots against the actual staged v6 terrain triangles."""
from pathlib import Path
import json,struct,hashlib,subprocess
import numpy as np
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3]
ASSETS=ROOT/'assets/landmarks/alcatraz_island';QA=ROOT/'output/alcatraz-nature-424/project'/ASSETS.relative_to(ROOT)
DOC=ROOT/'docs/design/alcatraz-nature-424'
def glb(path):
 data=path.read_bytes();n=struct.unpack_from('<I',data,12)[0];g=json.loads(data[20:20+n]);binary=data[28+n:]
 def accessor(i):
  a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]
  k={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']];offset=v.get('byteOffset',0)+a.get('byteOffset',0)
  item=np.dtype(dtype).itemsize
  return np.ndarray((a['count'],k),dtype=dtype,buffer=binary,offset=offset,strides=(v.get('byteStride',k*item),item))
 tris=[]
 for node in g['nodes']:
  if 'mesh' not in node:continue
  assert 'matrix' not in node and node.get('translation',[0,0,0])==[0,0,0]
  assert node.get('scale',[1,1,1])==[1,1,1] and node.get('rotation',[0,0,0,1])==[0,0,0,1]
  for p in g['meshes'][node['mesh']]['primitives']:
   verts=accessor(p['attributes']['POSITION']);index=accessor(p['indices']).reshape(-1)
   tris.append(verts[index].reshape(-1,3,3))
 return np.concatenate(tris)
def main():
 layout=json.loads((QA/'layout.json').read_text());proposal=json.loads((ASSETS/'alc_nature_placements.json').read_text())
 base=proposal['source_layout_commit'];terrain=[];unchanged=[]
 assert (QA/'layout.json').read_bytes()==(SRC/'reference/blockout_layout.json').read_bytes()
 for p in layout['placements']:
  if not p['asset'].startswith('alc_ground'):continue
  path=QA/(p['asset']+'.glb')
  assert path.read_bytes()==subprocess.check_output(['git','show',base+':assets/landmarks/alcatraz_island/'+path.name],cwd=ROOT)
  assert p['rotation_degrees']==[0,0,0] and p['scale']==[1,1,1]
  terrain.append(glb(path)+np.array(p['position']))
  unchanged.append({'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
 t=np.concatenate(terrain);a=t[:,0];b=t[:,1];c=t[:,2]
 den=(b[:,2]-c[:,2])*(a[:,0]-c[:,0])+(c[:,0]-b[:,0])*(a[:,2]-c[:,2])
 valid=abs(den)>1e-9;den=np.where(valid,den,1)
 rows=[]
 for p in proposal['points']:
  if 'rock' in p['asset']:continue
  x,y,z=p['position']
  u=((b[:,2]-c[:,2])*(x-c[:,0])+(c[:,0]-b[:,0])*(z-c[:,2]))/den
  v=((c[:,2]-a[:,2])*(x-c[:,0])+(a[:,0]-c[:,0])*(z-c[:,2]))/den
  hits=valid&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1+1e-6)
  heights=(u*a[:,1]+v*b[:,1]+(1-u-v)*c[:,1])[hits]
  assert len(heights)>0,(p['name'],'no terrain below root')
  h=float(heights[np.argmin(abs(heights-y))]);embed=h-y
  expected=.035 if 'shrub' in p['asset'] else .01
  assert abs(embed-expected)<.002,(p['name'],embed)
  rows.append({'name':p['name'],'terrain_y':h,'root_embed_m':round(embed,5)})
 result={'passed':True,'source_layout_commit':base,'terrain_bytes_unchanged':unchanged,'plant_roots_checked':len(rows),'roots':rows,
         'scope':'actual terrain triangles under each plant root; shoreline rocks intentionally intersect island foot, not treated as plants'}
 (DOC/'placement-support-validation.json').write_text(json.dumps(result,indent=2)+'\n')
 print('ALC_PLANT_SUPPORT_PASS',len(rows))
if __name__=='__main__':main()
