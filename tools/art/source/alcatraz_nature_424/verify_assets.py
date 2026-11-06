"""Inspect the delivered GLBs, not Blender's pre-export triangle counters."""
from pathlib import Path
import json,struct,math,hashlib
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];ASSETS=ROOT/'assets/landmarks/alcatraz_island';DOC=ROOT/'docs/design/alcatraz-nature-424'
def main():
 manifest=json.loads((ASSETS/'alc_nature_manifest.json').read_text());checks=[]
 def check(ok,label):
  checks.append({'check':label,'passed':bool(ok)});assert ok,label
 for name,spec in manifest['assets'].items():
  data=(ASSETS/spec['file']).read_bytes();magic,version,total=struct.unpack_from('<III',data)
  check(magic==0x46546c67 and version==2 and total==len(data),name+': GLB container')
  size,kind=struct.unpack_from('<II',data,12);g=json.loads(data[20:20+size]);offset=20+size;bs,bk=struct.unpack_from('<II',data,offset);binary=data[offset+8:offset+8+bs]
  def read(index):
   a=g['accessors'][index];b=g['bufferViews'][a['bufferView']];n={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']];f={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']];step=b.get('byteStride',struct.calcsize('<'+f*n));start=b.get('byteOffset',0)+a.get('byteOffset',0)
   return [struct.unpack_from('<'+f*n,binary,start+i*step) for i in range(a['count'])]
  check(len(g['meshes'])==1 and len(g['meshes'][0]['primitives'])==1,name+': one mesh/primitive')
  p=g['meshes'][0]['primitives'][0];indices=[a[0] for a in read(p['indices'])];verts=read(p['attributes']['POSITION']);normals=read(p['attributes']['NORMAL']);colors=read(p['attributes']['COLOR_0'])
  check(len(indices)//3==spec['triangles'] and len(indices)//3<=spec['triangle_limit'],name+': exported triangle count')
  check(all(0<=i<len(verts) for i in indices),name+': valid indices')
  check(all(all(math.isfinite(v) for v in x) for group in [verts,normals,colors] for x in group),name+': finite attributes')
  check(all(abs(sum(v*v for v in n)-1)<.002 for n in normals),name+': unit normals')
  def area(i,j,k):
   a=[verts[j][n]-verts[i][n] for n in range(3)];b=[verts[k][n]-verts[i][n] for n in range(3)];return sum(x*x for x in [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]])
  check(all(area(*indices[i:i+3])>1e-12 for i in range(0,len(indices),3)),name+': no degenerate triangles')
  check(len(g.get('materials',[]))==1 and not g.get('textures') and not g.get('images'),name+': self contained vertex material')
  m=g['materials'][0];check(m.get('alphaMode','OPAQUE')=='OPAQUE' and not m.get('doubleSided',False),name+': opaque with normal backface culling')
  check(m['pbrMetallicRoughness']['roughnessFactor']>=.9 and m['pbrMetallicRoughness']['metallicFactor']==0,name+': matte dielectric')
  check(not g.get('animations') and not g.get('skins'),name+': static MultiMesh prototype')
  check(hashlib.sha256(data).hexdigest()==spec['sha256'],name+': manifest hash')
 # Navigation footprint is checked independently of the generator's rectangles.
 layout=json.loads((SRC/'reference/blockout_layout.json').read_text());placements=json.loads((ASSETS/'alc_nature_placements.json').read_text());nav=layout['navigation'];rects=[]
 originals={p['name']:p for p in layout['placements'] if p.get('owner')=='刘备'}
 check(len(placements['points'])==len(originals)==114,'replace exactly 114 v6 owner points')
 check({p['source_name'] for p in placements['points']}==set(originals),'every source placement replaced once')
 check(placements['source_layout_sha256']==hashlib.sha256((SRC/'reference/blockout_layout.json').read_bytes()).hexdigest(),'pinned v6 layout hash')
 for polys in nav['zone_polygons'].values():
  for face in polys:
   vs=[nav['vertices'][i] for i in face];rects.append((min(p[0] for p in vs),max(p[0] for p in vs),min(p[2] for p in vs),max(p[2] for p in vs),sum(p[1] for p in vs)/len(vs)))
 for p in placements['points']:
  check(p['owner']=='刘备' and p['collision']==False and p['multimesh'],p['name']+': decoration metadata')
  original=originals[p['source_name']]
  expected=list(original['position']);expected[1]-=.035 if 'shrub' in p['asset'] else .01 if p['asset']=='alc_grass_tuft' else 0
  if p['name']=='alc_rock_c_003':expected[0]=-26.2
  check(p['position']==expected and p['rotation_degrees']==original['rotation_degrees'] and p['scale']==original['scale'] and p['zone']==original['zone'],p['name']+': only declared transform adjustments')
  x,y,z=p['position'];size=manifest['assets'][p['asset']]['dimensions_m'];r=math.hypot(size[0],size[2])*.5*p['scale'][0]
  hits=sum(1 for a,b,c,d,ny in rects if y<ny<y+size[1]*p['scale'][1]+.15 and math.hypot(max(a-x,0,x-b),max(c-z,0,z-d))<r+.15)
  check(hits==0,p['name']+': clear of original walk polygons')
 result={'passed':True,'checks':checks,'source_layout_commit':placements['source_layout_commit'],'assets':len(manifest['assets']),'unique_triangles':sum(a['triangles'] for a in manifest['assets'].values()),'replacement_instances':len(placements['points']),'placed_triangles':placements['placed_triangles']}
 DOC.mkdir(exist_ok=True,parents=True);(DOC/'asset-validation.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n');print('ALC_ASSETS_PASS',len(checks),'checks')
if __name__=='__main__':main()
