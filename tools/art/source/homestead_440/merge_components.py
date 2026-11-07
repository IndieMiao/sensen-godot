"""Join opaque GLB buffers into one surface without rounding the approved kit.

Blender custom split normals use angular compression. The editable scene keeps
the imported modules, but the runtime merge reads their original float32 values.
No transforms, recolouring, retriangulation or material passes are introduced.
"""
import json,struct
from verify_chef_sign import load_glb,accessor

def merge(path,sources):
 documents=[load_glb(p) for p in [path]+sources]
 doc=documents[0][0]
 vertices=[];lookup={};indices=[]
 for part,buffer in documents:
  assert len(part['meshes'])==1 and len(part['meshes'][0]['primitives'])==1
  for node in part['nodes']:
   assert node.get('translation',[0,0,0])==[0,0,0] and node.get('scale',[1,1,1])==[1,1,1]
   assert node.get('rotation',[0,0,0,1])==[0,0,0,1] and 'matrix' not in node
  primitive=part['meshes'][0]['primitives'][0]
  assert set(primitive['attributes'])=={'POSITION','NORMAL','COLOR_0'}
  arrays=[accessor(part,buffer,primitive['attributes'][key]) for key in ['POSITION','NORMAL','COLOR_0']]
  remap=[]
  for position,normal,color in zip(*arrays):
   assert len(color)==3 or color[3]==1
   key=position+normal+color[:3]
   if key not in lookup:lookup[key]=len(vertices);vertices.append(key)
   remap.append(lookup[key])
  indices.extend(remap[i[0]] for i in accessor(part,buffer,primitive['indices']))
 payload=bytearray();views=[];accessors=[]
 for semantic,offset in [('POSITION',0),('NORMAL',3),('COLOR_0',6)]:
  start=len(payload);values=[v[offset:offset+3] for v in vertices]
  for value in values:payload.extend(struct.pack('<3f',*value))
  views.append({'buffer':0,'byteOffset':start,'byteLength':len(payload)-start,'target':34962})
  a={'bufferView':len(views)-1,'componentType':5126,'count':len(vertices),'type':'VEC3'}
  if semantic=='POSITION':
   a['min']=[min(v[i] for v in values) for i in range(3)]
   a['max']=[max(v[i] for v in values) for i in range(3)]
  accessors.append(a)
 start=len(payload)
 payload.extend(struct.pack('<'+'I'*len(indices),*indices))
 views.append({'buffer':0,'byteOffset':start,'byteLength':len(payload)-start,'target':34963})
 accessors.append({'bufferView':3,'componentType':5125,'count':len(indices),'type':'SCALAR'})
 name=path.stem
 doc['nodes']=[{'name':name,'mesh':0}];doc['scenes']=[{'name':name,'nodes':[0]}];doc['scene']=0
 doc['meshes']=[{'name':name,'primitives':[{'attributes':{'POSITION':0,'NORMAL':1,'COLOR_0':2},'indices':3,'material':0,'mode':4}]}]
 doc['accessors']=accessors;doc['bufferViews']=views;doc['buffers']=[{'byteLength':len(payload)}]
 assert len(doc['materials'])==1 and not doc.get('images') and not doc.get('textures')
 encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
 binary=struct.pack('<III',0x46546c67,2,28+len(encoded)+len(payload))
 binary+=struct.pack('<I4s',len(encoded),b'JSON')+encoded
 binary+=struct.pack('<I4s',len(payload),b'BIN\0')+payload
 path.write_bytes(binary)
 return {'triangles':len(indices)//3,'bounds':[[round(v,6) for v in accessors[0][bound]] for bound in ['min','max']]}
