"""Inspect the delivered GLBs, not Blender's pre-export triangle counters."""
from pathlib import Path
import json,struct,math,hashlib
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];ASSETS=ROOT/'assets/landmarks/alcatraz_island';DOC=ROOT/'docs/design/alcatraz-dock-424'
def main():
 manifest=json.loads((ASSETS/'alc_dock_manifest.json').read_text());checks=[]
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
 # Validate the proposed central aisle and exit using exported mesh bounds.
 layout=json.loads((SRC/'reference/layout.json').read_text());placements=json.loads((ASSETS/'alc_dock_placements.json').read_text())
 rows=[]
 for p in placements['points']:
  check(p['owner']=='刘备' and not p['collision'] and not p['interaction'],p['name']+': decoration only')
  check(p['position'][1]==1 and p['zone']=='DockZone',p['name']+': dock floor / zone')
  a=manifest['assets'][p['asset']];angle=math.radians(p['rotation_degrees'][1]);sx,sy,sz=p['scale'];px,py,pz=p['position']
  corners=[(px+math.cos(angle)*x*sx+math.sin(angle)*z*sz,pz-math.sin(angle)*x*sx+math.cos(angle)*z*sz) for x in [a['bounds'][0][0],a['bounds'][1][0]] for z in [a['bounds'][0][2],a['bounds'][1][2]]]
  x0=min(x for x,z in corners);x1=max(x for x,z in corners);z0=min(z for x,z in corners);z1=max(z for x,z in corners)
  distance=math.hypot(max(x0+22,0,-22-x1),max(z0-19,0,19-z1))
  check(distance>=.50,p['name']+': >=0.50m spawn clearance')
  # Entire bounding footprint remains outside x=-22 +/-0.45m centre corridor.
  check(x1<=-22.45 or x0>=-21.55,p['name']+': 0.90m central aisle clear')
  if z1>14:check(x0>=-23.51 and x1<=-20.49 and z1<=20,p['name']+': on original 3m pier')
  else:check(x0>=-24 and x1<=-18 and z0>=10.5,p['name']+': on original plaza')
  rows.append({'name':p['name'],'footprint_xz':[x0,z0,x1,z1],'spawn_clearance_m':distance})
 check(sum(p['asset']=='alc_dock_planter' for p in placements['points'])==2,'exactly two large planters')
 check(len({p['asset'] for p in placements['points']})==5,'all five kit pieces placed')
 result={'passed':True,'checks':checks,'source_layout_commit':placements['source_layout_commit'],'assets':len(manifest['assets']),'unique_triangles':manifest['triangles_total'],'instances':len(placements['points']),'placed_triangles':sum(manifest['assets'][p['asset']]['triangles'] for p in placements['points']),'placement_bounds':rows,'central_aisle_m':.90}
 DOC.mkdir(exist_ok=True,parents=True);(DOC/'asset-validation.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n');print('ALC_DOCK_ASSETS_PASS',len(checks),'checks')
if __name__=='__main__':main()
