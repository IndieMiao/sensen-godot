"""Append hidden side liners to approved facade GLBs without rebaking originals.

Run in Blender under gs66-render.lock. Imports the accepted editable room source,
adds named liner objects, and appends the same triangles to each single surface.
Original POSITION/NORMAL/UV/COLOR and indices are retained byte for byte.
"""
from pathlib import Path
import bpy,sys,json,struct,subprocess,hashlib,copy
import numpy as np
ROOT=Path(__file__).resolve().parents[4];HERE=Path(__file__).resolve().parent
OUT=ROOT/'assets/rooms/market_plaza';TMP=ROOT/'output/market-facade-seams-218';TMP.mkdir(parents=True,exist_ok=True)
BASE='c7a0a4b6a'
sys.path.insert(0,str(ROOT/'tools/art'))
from landmark_kit import hex_rgb
DT={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}
WIDTH={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}
def load_glb(raw):
 n=struct.unpack_from('<I',raw,12)[0];return json.loads(raw[20:20+n]),raw[28+n:]
def accessor(doc,blob,index):
 a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];dt=np.dtype(DT[a['componentType']]);width=WIDTH[a['type']]
 return np.ndarray((a['count'],width),dtype=dt,buffer=blob,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',dt.itemsize*width),dt.itemsize)).copy()
def box_faces(x0,x1,y0,y1,z0,z1):
 # Each face uses independent vertices and exact flat normals.
 sides=[([(x0,y0,z0),(x0,y0,z1),(x0,y1,z1),(x0,y1,z0)],(-1,0,0)),
        ([(x1,y0,z1),(x1,y0,z0),(x1,y1,z0),(x1,y1,z1)],(1,0,0)),
        ([(x0,y0,z0),(x1,y0,z0),(x1,y0,z1),(x0,y0,z1)],(0,-1,0)),
        ([(x0,y1,z1),(x1,y1,z1),(x1,y1,z0),(x0,y1,z0)],(0,1,0)),
        ([(x1,y0,z0),(x0,y0,z0),(x0,y1,z0),(x1,y1,z0)],(0,0,-1)),
        ([(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)],(0,0,1))]
 p=[];n=[];uv=[];ix=[]
 for pts,normal in sides:
  first=len(p);p.extend(pts);n.extend([normal]*4);uv.extend([(0,0),(1,0),(1,1),(0,1)]);ix.extend([first,first+1,first+2,first,first+2,first+3])
 return np.array(p),np.array(n),np.array(uv),np.array(ix).reshape(-1,1)
def append(raw,extra):
 source_doc,blob=load_glb(raw);doc=copy.deepcopy(source_doc);primitive=doc['meshes'][0]['primitives'][0]
 assert len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1
 count=doc['accessors'][primitive['attributes']['POSITION']]['count'];binary=bytearray()
 assert set(primitive['attributes'].values())|{primitive['indices']}==set(range(len(doc['accessors'])))
 doc['bufferViews']=[]
 def write(index,array):
  a=doc['accessors'][index];original=accessor(source_doc,blob,index);a.pop('byteOffset',None)
  combined=np.concatenate([original,array.astype(original.dtype)])
  while len(binary)%4:binary.append(0)
  offset=len(binary);data=combined.tobytes();binary.extend(data)
  view={'buffer':0,'byteOffset':offset,'byteLength':len(data)}
  oldview=source_doc['bufferViews'][source_doc['accessors'][index]['bufferView']]
  if 'target' in oldview:view['target']=oldview['target']
  a['bufferView']=len(doc['bufferViews']);doc['bufferViews'].append(view);a['count']=len(combined)
  if 'min' in a:a['min']=combined.min(axis=0).tolist()
  if 'max' in a:a['max']=combined.max(axis=0).tolist()
 for semantic,index in primitive['attributes'].items():
  a=doc['accessors'][index];new=extra.get(semantic)
  if new is None:
   new=np.zeros((len(extra['POSITION']),WIDTH[a['type']]))
   if semantic=='TANGENT':new[:,0]=1;new[:,3]=1
  if a.get('normalized') and a['componentType']!=5126:new=np.round(new*np.iinfo(np.dtype(DT[a['componentType']])).max)
  write(index,new)
 write(primitive['indices'],extra['indices']+count)
 while len(binary)%4:binary.append(0)
 doc['buffers'][0]['byteLength']=len(binary)
 data=json.dumps(doc,separators=(',',':')).encode();data+=b' '*((-len(data))%4)
 return struct.pack('<III',0x46546c67,2,28+len(data)+len(binary))+struct.pack('<II',len(data),0x4e4f534a)+data+struct.pack('<II',len(binary),0x004e4942)+binary
def main():
 source=TMP/'baseline_market.blend';source.write_bytes(subprocess.check_output(['git','show',BASE+':tools/art/source/market_plaza/market_plaza.blend'],cwd=ROOT))
 bpy.ops.wm.open_mainfile(filepath=str(source));bpy.context.preferences.filepaths.save_version=0
 palette=json.loads(json.dumps({'generic':['C6B38C','AA7E65','969E8B','D9D5C8'],'sf':['6398BC','D5888C','E8D1A4','DDB354','7DAE9A','6398BC','D5888C','E8D1A4']}))
 records={};stats=json.loads((OUT/'shell_asset_stats.json').read_text())
 for kind,num in [('generic',4),('sf',8)]:
  for i in range(num):
   name=f'facade_{kind}_{i}';raw=subprocess.check_output(['git','show',BASE+':assets/rooms/market_plaza/'+name+'.glb'],cwd=ROOT);doc,blob=load_glb(raw)
   (TMP/(name+'-before.glb')).write_bytes(raw)
   eave=6 if i%2==0 else 6.4;color=np.array([*hex_rgb(palette[kind][i]),1.0]);color[:3]*=.80
   original_positions=accessor(doc,blob,doc['meshes'][0]['primitives'][0]['attributes']['POSITION'])
   # 0.1 mm weld allowance prevents the perpendicular corner's two 30 mm
   # extensions from merely touching after float32 GLB/world transforms.
   outer=float(np.abs(original_positions[:,0]).max())+.0301
   mat=bpy.data.materials.new(name+'_recessed_wall');mat.diffuse_color=tuple(color)
   arrays=[];liners=[]
   for side in [-1,1]:
    # Extend 3 cm beyond each approved model's edge. Inboard overlap reaches
    # under its 3.92 m wall. The right liner at the inner corner is the front
    # member; the left is 2 mm deeper so adjacent liners never coplane.
    x0,x1=(-outer,-1.94) if side<0 else (1.94,outer)
    front=1.228 if side<0 else 1.230
    p,n,uv,ix=box_faces(x0,x1,0,eave-.005,-1.245,front)
    mesh=bpy.data.meshes.new(name+('_left' if side<0 else '_right')+'_liner')
    mesh.from_pydata([(x,-z,y) for x,y,z in p],[],ix.reshape(-1,3).tolist());mesh.update()
    obj=bpy.data.objects.new(mesh.name,mesh);bpy.data.collections[name].objects.link(obj);mesh.materials.append(mat)
    obj['purpose']='Recessed opaque joint backing; no new collision';obj['front_setback_m']=1.25-front
    arrays.append((p,n,uv,ix));liners.append({'side':side,'x':[x0,x1],'y':[0,eave-.005],'z':[-1.245,front],'front_setback_m':1.25-front})
   p=np.concatenate([a[0] for a in arrays]);n=np.concatenate([a[1] for a in arrays]);uv=np.concatenate([a[2] for a in arrays]);ix=np.concatenate([arrays[0][3],arrays[1][3]+24])
   extra={'POSITION':p,'NORMAL':n,'TEXCOORD_0':uv,'COLOR_0':np.tile(color,(len(p),1)),'indices':ix}
   updated=append(raw,extra);(OUT/(name+'.glb')).write_bytes(updated)
   oldcount=doc['accessors'][doc['meshes'][0]['primitives'][0]['indices']]['count']//3
   stats['assets'][name]={'triangles':oldcount+24,'bytes':len(updated)}
   records[name]={'before_triangles':oldcount,'after_triangles':oldcount+24,'added_triangles':24,'surfaces':1,'liners':liners,'wall_srgb':palette[kind][i],'liner_linear_rgb':color[:3].tolist(),'sha256':hashlib.sha256(updated).hexdigest()}
 bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'market_facade_seams.blend'))
 (OUT/'shell_asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
 (HERE/'manifest.json').write_text(json.dumps({'base':BASE,'original_attributes_preserved':True,'roof_extension':'none; approved roof geometry retained','assets':records},indent=2)+'\n')
 print('FACADE_LINERS_BUILT 12 assets; +24 triangles per asset; original surfaces preserved')
if __name__=='__main__':main()
