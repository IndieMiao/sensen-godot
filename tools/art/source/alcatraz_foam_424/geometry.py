from pathlib import Path
import json,struct,numpy as np

def read_glb(path):
 raw=Path(path).read_bytes();n=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+n]);binary=raw[28+n:]
 def accessor(i):
  a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']];k={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];item=np.dtype(dtype).itemsize
  arr=np.ndarray((a['count'],k),dtype=dtype,buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',item*k),item))
  if a.get('normalized'):arr=arr.astype(float)/np.iinfo(arr.dtype).max
  return arr
 records=[]
 for node in g['nodes']:
  if 'mesh' not in node:continue
  assert node.get('translation',[0,0,0])==[0,0,0] and node.get('rotation',[0,0,0,1])==[0,0,0,1] and node.get('scale',[1,1,1])==[1,1,1]
  for prim in g['meshes'][node['mesh']]['primitives']:
   records.append({**{k:accessor(v) for k,v in prim['attributes'].items()},'indices':accessor(prim['indices']).reshape(-1)})
 return g,records

def triangles(path):
 return np.concatenate([p['POSITION'][p['indices']].reshape(-1,3,3) for p in read_glb(path)[1]])

def section(tris,y):
 segments=[]
 for t in tris:
  points=[]
  for a,b in [(t[0],t[1]),(t[1],t[2]),(t[2],t[0])]:
   if (a[1]-y)*(b[1]-y)<0:
    p=a+(b-a)*(y-a[1])/(b[1]-a[1]);points.append(p[[0,2]])
  if len(points)==2 and np.linalg.norm(points[0]-points[1])>1e-6:segments.append(points)
 return np.array(segments)

def exterior(segments,count=720):
 # Host footprint is star-shaped about (0,0); choose outermost crossing per ray.
 a=segments[:,0];v=segments[:,1]-a;result=[]
 cross=lambda x,y:x[...,0]*y[...,1]-x[...,1]*y[...,0]
 for theta in np.linspace(0,2*np.pi,count,endpoint=False):
  d=np.array([np.cos(theta),np.sin(theta)]);den=cross(d,v);valid=abs(den)>1e-8;safe=np.where(valid,den,1);r=cross(a,v)/safe;t=cross(a,d)/safe
  hits=valid&(r>0)&(t>=0)&(t<=1);assert hits.any(),theta
  result.append(d*np.max(r[hits]))
 return np.array(result)
