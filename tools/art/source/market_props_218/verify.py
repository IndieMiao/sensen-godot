"""Audit exported buffers, independent of Blender evaluated statistics."""
from pathlib import Path
import json,hashlib,re,sys,argparse,collections
import numpy as np
ROOT=Path(__file__).resolve().parents[4];KIT=ROOT/'assets/rooms/market_plaza'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('--skip-imports',action='store_true');args=ap.parse_args()
stats=json.loads((KIT/'asset_stats.json').read_text());checks=[];rows=[];uids=[]
def check(ok,label,evidence=None):checks.append({'passed':bool(ok),'check':label,'evidence':evidence})
for row in stats['assets']:
 name=row['name'];path=KIT/row['file'];doc,buf=load_glb(path)
 check(len(doc.get('meshes',[]))==1 and len(doc['meshes'][0]['primitives'])==1,name+' one mesh and one surface')
 pr=doc['meshes'][0]['primitives'][0];v=np.array(accessor(doc,buf,pr['attributes']['POSITION']));idx=np.array(accessor(doc,buf,pr['indices'])).reshape(-1,3);n=np.array(accessor(doc,buf,pr['attributes']['NORMAL']));c=np.array(accessor(doc,buf,pr['attributes']['COLOR_0']))
 tri=v[idx];bounds=np.array([v.min(0),v.max(0)]);dims=np.ptp(v,axis=0)
 check(len(idx)==row['triangles'] and len(idx)<=row['triangle_limit'],name+' triangles within budget',len(idx))
 check(np.allclose(bounds,row['bounds'],atol=1e-6),name+' actual vertex bounds match stats',bounds.tolist())
 check(np.allclose(dims,row['dimensions_m'],atol=1e-6),name+' actual dimensions match stats',dims.tolist())
 check(path.stat().st_size==row['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256'],name+' bytes and SHA256')
 check(np.isfinite(v).all() and np.isfinite(n).all() and np.isfinite(c).all(),name+' finite geometry and colours')
 check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),name+' no degenerate faces')
 edges=collections.Counter()
 for t in tri:
  q=[tuple(np.round(point,6)) for point in t]
  for j in range(3):edges[tuple(sorted((q[j],q[(j+1)%3])))]+=1
 check(not any(count==1 for count in edges.values()),name+' closed shells, no boundary edges',sum(count==1 for count in edges.values()))
 check(abs(bounds[0,1])<1e-6,name+' ground is Y0')
 check(doc['meshes'][0]['name']==name+'_mobile',name+' mesh name')
 check(not doc.get('animations') and not doc.get('skins') and not doc.get('cameras') and not doc.get('images') and not doc.get('textures') and not doc.get('extensions',{}).get('KHR_lights_punctual'),name+' static texture-free prop only')
 check(len(doc['materials'])==1 and doc['materials'][0]['pbrMetallicRoughness']['roughnessFactor']>=.85,name+' one matte material')
 if name.startswith('stall_'):
  w=3.2 if name=='stall_keeper' else 2.;h=3.1 if name=='stall_keeper' else 2.6
  check(np.allclose(dims[[0,2]],[w,1.6],atol=1e-5) and dims[1]<=h,name+' hard footprint and height',dims.tolist())
 if name=='flower_cart':check(np.allclose(dims[[0,2]],[2,1.4],atol=1e-5) and dims[1]<=2.4,name+' hard cart dimensions')
 if name=='market_board':check(np.allclose(dims,[1.2,1.8,.3],atol=1e-5),name+' hard board dimensions')
 if name=='fountain':check(np.allclose(dims[[0,2]],[3,3],atol=1e-5) and dims[1]<=2.2,name+' fountain diameter and height')
 if name=='stall_keeper':
  zone=row['keeper_clearance_local_m'];low=np.array(zone['min']);high=np.array(zone['max']);overlap=((tri.max(1)>low+1e-6)&(tri.min(1)<high-1e-6)).all(1)
  check(not overlap.any(),'Mei rear 0.80m work lane has no model faces',{'box':zone,'overlapping_triangle_bounds':int(overlap.sum())})
 if not args.skip_imports:
  cfg=Path(str(path)+'.import').read_text();uid=re.search(r'uid="(uid://[a-y0-8]+)"',cfg);uids.append(uid.group(1) if uid else '')
  check(uid is not None,name+' engine-generated valid UID')
  check('nodes/root_script=null' in cfg and 'gltf/texture_map_mode=1' in cfg,name+' root_script and import convention')
 rows.append({'name':name,'triangles':len(idx),'dimensions_m':dims.tolist(),'bytes':path.stat().st_size,'sha256':row['sha256']})
if not args.skip_imports:check(len(set(uids))==12,'12 unique Godot UIDs')
check(len(rows)==12,'All 12 requested reusable models')
report={'task':'SGODOT-218','stage':stats['stage'],'checks':checks,'passed':all(x['passed'] for x in checks),'assets':rows,'total_triangles':sum(r['triangles'] for r in rows)}
args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('MARKET_AUDIT',report['passed'],len(checks),report['total_triangles'])
raise SystemExit(0 if report['passed'] else 1)
