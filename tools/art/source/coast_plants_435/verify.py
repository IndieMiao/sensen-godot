"""Verify exported geometry, solid foliage, shared LOD pivots and import contract."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys
import numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];KIT=ROOT/'assets/landmarks/_shared/coast_plants';QA=ROOT/'output/coast-plants'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
parser=argparse.ArgumentParser();parser.add_argument('--geometry-only',action='store_true');args=parser.parse_args()
data=json.loads((KIT/'manifest.json').read_text());report={'checks':[],'assets':{},'author':'赵云'};uids=[]
def check(ok,label):
 report['checks'].append({'passed':bool(ok),'check':label})
 if not ok:print('FAIL',label)
for name,e in data['assets'].items():
 path=KIT/(name+'.glb');doc,blob=load_glb(path);p=doc['meshes'][0]['primitives'][0]
 xyz=np.array(accessor(doc,blob,p['attributes']['POSITION']));normal=np.array(accessor(doc,blob,p['attributes']['NORMAL']));colors=np.array(accessor(doc,blob,p['attributes']['COLOR_0']));ids=np.array(accessor(doc,blob,p['indices'])).reshape(-1,3)
 budget=120 if e['lod']=='far' else 800 if e['lod']=='near' else 400
 check(len(doc['meshes'])==1 and len(doc['meshes'][0]['primitives'])==1 and doc['meshes'][0]['name']==name+'_mobile',name+': single mobile mesh / surface')
 check(len(doc['nodes'])==1 and doc['nodes'][0]=={'mesh':0,'name':name},name+': identity node and local root')
 check(len(ids)<=budget and len(ids)==e['triangles'],name+': measured triangles within budget')
 check(not any(doc.get(k) for k in ['skins','animations','textures','images']),name+': no texture / skin / animation')
 check(set(p['attributes'])=={'POSITION','NORMAL','COLOR_0'},name+': vertex paint without texture coordinates')
 check(np.isfinite(xyz).all() and np.isfinite(normal).all() and np.isfinite(colors).all(),name+': finite vertex attributes')
 check(np.allclose(np.linalg.norm(normal,axis=1),1,atol=1e-4),name+': normalized normals')
 check(np.all(colors>=-1e-6) and np.all(colors<=1.000001) and (colors.shape[1]==3 or np.allclose(colors[:,3],1)),name+': opaque bounded vertex colours')
 mat=doc['materials'][0];pbr=mat['pbrMetallicRoughness']
 check(len(doc['materials'])==1 and mat.get('alphaMode','OPAQUE')=='OPAQUE' and not mat.get('doubleSided',False) and pbr['metallicFactor']==0 and abs(pbr['roughnessFactor']-.9)<1e-6,name+': single opaque matte material, culled solid geometry')
 lo=xyz.min(0);hi=xyz.max(0)
 check(np.allclose([lo,hi],e['bounds'],atol=1e-6) and abs(lo[1])<1e-6,name+': grounded and manifest bounds match')
 if e['lod']=='single':check(np.allclose((lo+hi)[[0,2]],0,atol=1e-6),name+': footprint-centred scatter pivot')
 face=np.cross(xyz[ids[:,1]]-xyz[ids[:,0]],xyz[ids[:,2]]-xyz[ids[:,0]]);areas=np.linalg.norm(face,axis=1);dots=np.sum(face*normal[ids].mean(1),axis=1)
 check(np.all(areas>1e-10),name+': no zero-area triangles')
 check(np.all(dots>0),name+': outward geometric / shading normal agreement')
 # Weld by position for the closed-surface edge check; colour/normal splits are intentional.
 keys=[tuple(np.round(v,6)) for v in xyz];edges={}
 for a,b,c in ids:
  for v,w in [(a,b),(b,c),(c,a)]:
   key=tuple(sorted([keys[v],keys[w]]));edges[key]=edges.get(key,0)+1
 check(all(n%2==0 for n in edges.values()),name+': no open edges, leaves and canopy have undersides')
 if name!='coast_grass_a':
  previous=subprocess.check_output(['git','show','a4565284:assets/landmarks/_shared/coast_plants/'+name+'.glb'],cwd=ROOT)
  check(path.read_bytes()==previous,name+': v1.1 GLB byte-identical')
 if name=='coast_grass_a':
  check(len(ids)==144 and e['leaf_count']==18 and e['seed_heads']==0,name+': eighteen leaf blades only')
  # The accepted leaf geometry remains an exact subset of the original export.
  old_path=QA/'v1.2/grass_a_with_heads.glb';old_path.parent.mkdir(parents=True,exist_ok=True)
  old_path.write_bytes(subprocess.check_output(['git','show','a4565284:assets/landmarks/_shared/coast_plants/coast_grass_a.glb'],cwd=ROOT))
  old,old_blob=load_glb(old_path);op=old['meshes'][0]['primitives'][0]
  ox=np.array(accessor(old,old_blob,op['attributes']['POSITION']));on=np.array(accessor(old,old_blob,op['attributes']['NORMAL']));oc=np.array(accessor(old,old_blob,op['attributes']['COLOR_0']));oi=np.array(accessor(old,old_blob,op['indices'])).reshape(-1,3)
  # Removing the tilted seed-stalk caps changes the minimum Y by 0.42 mm.
  # Re-ground the leaves as a rigid translation; their shape and paint are retained.
  nearest=np.linalg.norm(xyz[:,None]-ox[None,:],axis=2).argmin(1)
  offset=np.median(ox[nearest]-xyz,axis=0)
  def position_triangles(points,triangles):
   return {tuple(sorted(tuple(np.round(points[v],6)) for v in tri)) for tri in triangles}
  check(position_triangles(xyz+offset,ids).issubset(position_triangles(ox,oi)) and np.allclose(offset[[0,2]],0,atol=1e-7),name+': original leaf shapes retained after grounding')
  check(np.allclose(normal,on[nearest],atol=2e-4) and np.array_equal(colors,oc[nearest]),name+': original leaf shading and paint retained')
  report['grass_cleanup']={'removed_triangles':len(oi)-len(ids),'leaf_count':18,'seed_heads':0,'grounding_translation_m':(-offset).tolist()}
  seed=np.array([int('C4B780'[i:i+2],16)/255 for i in [0,2,4]]);seed=np.where(seed<=.04045,seed/12.92,((seed+.055)/1.055)**2.4)
  check(np.linalg.norm(colors[:,:3]-seed,axis=1).min()>.01,name+': no pale seed-head vertices')
 if name=='coast_shrub_a':
  old_path=QA/'v1.1/shrub_a_v1.glb';old_path.write_bytes(subprocess.check_output(['git','show','a590b559:assets/landmarks/_shared/coast_plants/coast_shrub_a.glb'],cwd=ROOT))
  old,old_blob=load_glb(old_path);old_p=old['meshes'][0]['primitives'][0]
  for attr,current in [('POSITION',xyz),('NORMAL',normal),('indices',ids.reshape(-1,1))]:
   previous=np.array(accessor(old,old_blob,old_p['indices'] if attr=='indices' else old_p['attributes'][attr]))
   check(np.array_equal(previous,current),name+': accepted '+attr+' preserved')
  old_colors=np.array(accessor(old,old_blob,old_p['attributes']['COLOR_0']))
  check(float(np.mean(colors[:,1]-colors[:,0]))>float(np.mean(old_colors[:,1]-old_colors[:,0])),name+': vertex paint moves toward green while retaining muted palette')
 if name.startswith('coast_cypress'):
  # Recover disconnected cloud components from actual exported triangles.
  table={};parent=[];vertex_ids=[]
  for key in keys:
   if key not in table:table[key]=len(parent);parent.append(len(parent))
   vertex_ids.append(table[key])
  def root_of(x):
   while parent[x]!=x:parent[x]=parent[parent[x]];x=parent[x]
   return x
  for tri in ids:
   a,b,c=[vertex_ids[v] for v in tri];parent[root_of(b)]=root_of(a);parent[root_of(c)]=root_of(a)
  groups={}
  for tri in ids:groups.setdefault(root_of(vertex_ids[tri[0]]),[]).append(tri)
  clouds=[];trunk=None
  for group in groups.values():
   points=xyz[np.unique(np.array(group))];bounds=np.array([points.min(0),points.max(0)])
   if len(group)==(12 if e['lod']=='far' else 72):clouds.append(bounds)
   if abs(bounds[0,1])<1e-6:trunk=points
  clouds.sort(key=lambda box:float(box[:,1].mean()))
  check(len(clouds)==8,name+': four paired cloud layers in exported mesh')
  spans=[]
  if len(clouds)==8:
   for j in range(0,8,2):spans.append(float(max(clouds[j][1,0],clouds[j+1][1,0])-min(clouds[j][0,0],clouds[j+1][0,0])))
  check(len(spans)==4 and all(a>b for a,b in zip(spans,spans[1:])),name+': cloud layers shorten upward')
  check(trunk is not None and float(trunk[np.isclose(trunk[:,1],trunk[:,1].max()),0].mean())>1.9,name+': stronger +X trunk bend')
  report.setdefault('cypress_layers',{})[name]={'measured_layer_spans_m':spans,'cloud_components':len(clouds)}
 if e['family']=='iceplant':
  # Count separately welded components: a solid cushion, fleshy leaves, blooms.
  lookup={};parent=[];vertex_ids=[]
  for key in keys:
   if key not in lookup:lookup[key]=len(parent);parent.append(len(parent))
   vertex_ids.append(lookup[key])
  def find(x):
   while parent[x]!=x:parent[x]=parent[parent[x]];x=parent[x]
   return x
  for tri in ids:
   a,b,c=[vertex_ids[v] for v in tri];parent[find(b)]=find(a);parent[find(c)]=find(a)
  counts={}
  for tri in ids:
   root=find(vertex_ids[tri[0]]);counts[root]=counts.get(root,0)+1
  check(list(counts.values()).count(8)==e['short_leaf_count'],name+': actual short solid leaf count')
  check(list(counts.values()).count(20)==e['flower_count'],name+': actual pink blossom count')
  check(list(counts.values()).count(46)==1,name+': one continuous closed cushion')
  # Sample a central rectangle through all up-facing triangles: no bare gaps.
  triangles=xyz[ids[face[:,1]>1e-9]];a=triangles[:,0][:,[0,2]];u=triangles[:,1][:,[0,2]]-a;v=triangles[:,2][:,[0,2]]-a
  det=u[:,0]*v[:,1]-u[:,1]*v[:,0];good=np.abs(det)>1e-10;a=a[good];u=u[good];v=v[good];det=det[good]
  w,d=e['cushion_size_m'];hits=0
  for x in np.linspace(-w*.36,w*.36,17):
   for z in np.linspace(-d*.36,d*.36,13):
    q=np.array([x,z])-a;first=(q[:,0]*v[:,1]-q[:,1]*v[:,0])/det;second=(u[:,0]*q[:,1]-u[:,1]*q[:,0])/det
    hits+=bool(np.any((first>=-1e-6)&(second>=-1e-6)&(first+second<=1+1e-6)))
  check(hits==221,name+': central cushion coverage is continuous at all 221 samples')
  report.setdefault('cushions',{})[name]={'leaves':e['short_leaf_count'],'blooms':e['flower_count'],'covered_samples':hits,'samples':221}
 if name.startswith('coast_palm'):
  bottom=xyz[np.isclose(xyz[:,1],0,atol=1e-6)]
  check(np.isclose(bottom[:,0].max()-bottom[:,0].min(),.22,atol=1e-6),name+': slimmer .22m trunk base')
  dx=xyz[:,0]-.65;dz=xyz[:,2];radius=np.hypot(dx,dz);angle=np.arctan2(dz,dx)
  sectors=np.rint((angle-.22)/(np.pi/4)).astype(int)%8;leaf_data=[]
  for sector in range(8):
   points=xyz[(sectors==sector)&(radius>1.5)]
   ok=len(points)>0 and points[:,1].min()<4.3
   check(ok,name+': radial leaf '+str(sector)+' has a descending tip')
   leaf_data.append({'sector':sector,'tip_y':float(points[:,1].min()) if len(points) else None})
  check(xyz[:,1].max()>5.5 and e['frond_count']==8,name+': arched canopy above 5.15m crown root')
  if e['lod']=='near':
   rgb=np.array([int('795F47'[i:i+2],16)/255 for i in [0,2,4]]);linear=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
   band_points=xyz[np.linalg.norm(colors[:,:3]-linear,axis=1)<1e-6]
   check(all(np.any(np.isclose(band_points[:,1],h,atol=1e-6)) and np.any(np.isclose(band_points[:,1],h+.045,atol=1e-6)) for h in e['ring_heights_m']),name+': six narrow vertex-painted trunk rings')
  report.setdefault('palm_fronds',{})[name]=leaf_data
 sha=hashlib.sha256(path.read_bytes()).hexdigest();check(sha==e['sha256'],name+': exported SHA matches manifest')
 uid=None
 if not args.geometry_only:
  s=(KIT/(name+'.glb.import')).read_text();m=re.search(r'^uid="(uid://[^"]+)"$',s,re.M);uid=m.group(1) if m else None;uids.append(uid)
  check(uid is not None and all(x in s.splitlines() for x in ['nodes/root_script=null','gltf/texture_map_mode=1','meshes/light_baking=1','meshes/generate_lods=false']),name+': generated UID and stable import settings')
  previous=subprocess.check_output(['git','show','a590b559:assets/landmarks/_shared/coast_plants/'+name+'.glb.import'],cwd=ROOT)
  check((KIT/(name+'.glb.import')).read_bytes()==previous,name+': accepted import UID and settings retained')
 report['assets'][name]={'triangles':len(ids),'budget':budget,'surface_count':1,'sha256':sha,'bounds':[lo.tolist(),hi.tolist()],'uid':uid,'reversed_faces':int((dots<=0).sum()),'open_edges':sum(n%2!=0 for n in edges.values())}
for group in data['lod_groups']:
 near=report['assets'][group['near']];far=report['assets'][group['far']]
 check(np.allclose(near['bounds'],far['bounds'],atol=1e-5),group['near']+': near/far shared envelope and origin')
 check(group['switch_distance_m']==40 and group['margin_m']==0,group['near']+': 40m switch contract')
check(len(data['assets'])==10 and len(data['lod_groups'])==2,'six ground prototypes plus two near/far tree pairs')
check(not any(KIT.glob('*layout*')) and not data['example_layout_included'],'no delivered example layout')
check(json.loads((HERE/'asset_stats.json').read_text())==data,'source and runtime stats match')
if not args.geometry_only:check(len(set(uids))==10,'ten distinct Godot-generated UIDs')
changed=subprocess.check_output(['git','diff','--name-only','--diff-filter=MDRCT','7214c718','--'],cwd=ROOT,text=True).splitlines()
check(not changed,'all previously tracked files preserved')
report['triangles_total']=sum(a['triangles'] for a in report['assets'].values());report['passed']=all(c['passed'] for c in report['checks'])
(QA/('geometry-preimport.json' if args.geometry_only else 'asset-validation.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('COAST_PLANTS_VERIFY',report['passed'],len(report['checks']),'checks;',report['triangles_total'],'triangles')
raise SystemExit(0 if report['passed'] else 1)
