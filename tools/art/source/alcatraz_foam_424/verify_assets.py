"""Read delivered GLB triangles/UVs and unchanged host bytes, independent of Blender counters."""
from pathlib import Path
import json,hashlib,subprocess,numpy as np
from PIL import Image
from geometry import read_glb
S=Path(__file__).resolve().parent;R=S.parents[3];A=R/'assets/landmarks/alcatraz_island';D=R/'docs/design/alcatraz-foam-424';Q=R/'output/alcatraz-foam-424/project';P=json.loads((S/'provenance.json').read_text());M=json.loads((A/'alc_shore_foam_manifest.json').read_text());checks=[]
def check(ok,label):
 checks.append({'passed':bool(ok),'check':label});assert ok,label
for name,spec in M['assets'].items():
 path=A/spec['file'];g,meshes=read_glb(path);check(len(g['meshes'])==len(meshes)==1,name+': single mesh and surface');p=meshes[0];pos=p['POSITION'];idx=p['indices'];normal=p['NORMAL'];colors=p['COLOR_0']
 check(len(idx)//3==spec['triangles'] and len(idx)//3<=spec['triangle_limit'],name+': real index triangle budget')
 check(all(np.isfinite(v).all() for k,v in p.items()),name+': finite attributes');check(np.max(abs(np.linalg.norm(normal,axis=1)-1))<.002,name+': unit normals')
 tri=pos[idx].reshape(-1,3,3);areas=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)
 check(np.min(areas)>1e-7,name+': no degenerate triangles')
 check(len(g['materials'])==1 and not g.get('images') and not g.get('textures'),name+': single material without duplicated texture embeds')
 check(not g.get('animations') and not g.get('skins'),name+': static decorative prototype')
 check(hashlib.sha256(path.read_bytes()).hexdigest()==spec['sha256'],name+': manifest hash')
 bounds=np.stack([pos.min(axis=0),pos.max(axis=0)]);check(np.max(abs(bounds-np.array(spec['bounds'])))<.0001,name+': exported bounds match manifest')
 check(abs(bounds[:,0].sum())<.001 and abs(bounds[:,2].sum())<.001,name+': local horizontal centre')
 if name.startswith('alc_foam'):
  check(abs(pos[:,1]).max()<.00001,name+': exact flat water-plane mesh')
  check(normal[:,1].min()>.99,name+': upward facing')
  uv=p['TEXCOORD_0'];check(uv.shape[1]==2 and np.isfinite(uv).all(),name+': finite shared alpha UVs')
  check(colors[:,3].max()<=1 and colors[:,3].min()>=0,name+': bounded vertex alpha')
  if name!='alc_foam_ring':check(colors[:,3].min()==0,name+': fade both strip ends')
 else:check(bounds[0,1]<0<bounds[1,1],name+': origin at floating waterline')
img=np.array(Image.open(A/'alc_foam_soft.png'))
check(img.shape==(128,512,4),'one 512x128 RGBA foam texture')
check(np.array_equal(img[:,0],img[:,-1]),'periodic alpha texture seam')
check(img[0,:,3].max()==img[-1,:,3].max()==0,'cross-band borders fully transparent')
check(img[:,:,3].max()<=122 and np.count_nonzero(img[:,:,3]>0)>10000,'low contrast soft foam coverage')
placements=json.loads((A/'alc_shore_foam_placements.json').read_text());seen=set()
for row in placements['points']:
 check(row['name'] not in seen and row['owner']=='刘备',row['name']+': unique authored instance');seen.add(row['name'])
 check(not row['collision'] and not row['interaction'] and not row['cast_shadow'] and row['multimesh'],row['name']+': decorative batched instance')
 check(abs(row['position'][1]-(-.132 if row['asset'].startswith('alc_foam') else -.15))<1e-7,row['name']+': water level and overlay separation')
check(sum(placements['counts'].values())==len(seen),'placement counts match instances')
check(placements['placed_triangles']==sum(M['assets'][r['asset']]['triangles'] for r in placements['points']),'placed triangle budget')
# No host scene/material/nav/terrain edits hidden in the isolated review project.
files=['layout.json','placement_points.json','sea_backdrop.gdshader','far_card.gdshader','alc_ground_dock.glb','alc_ground_terraces.glb','alc_ground_summit.glb','dock.glb','alc_far_bridge.glb','alc_far_city.glb']
records=[]
for rel in ['assets/landmarks/alcatraz_island/'+n for n in files]+['scenes/landmark/alcatraz_island.gd','scenes/landmark/alcatraz_island.tscn']:
 data=(Q/rel).read_bytes();check(data==subprocess.check_output(['git','show',P['host_commit']+':'+rel],cwd=R),rel+': host unchanged');records.append({'file':rel,'sha256':hashlib.sha256(data).hexdigest()})
(D/'asset-validation.json').write_text(json.dumps({'passed':True,'checks':checks,'assets':len(M['assets']),'unique_triangles':M['unique_triangles'],'instances':len(seen),'batches':placements['batches'],'placed_triangles':placements['placed_triangles'],'host_commit':P['host_commit'],'unchanged_host_files':records},indent=2,ensure_ascii=False)+'\n')
print('ALC_FOAM_ASSET_PASS',len(checks))
