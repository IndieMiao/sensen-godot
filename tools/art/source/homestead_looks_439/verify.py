"""Inspect exported geometry, protected row 14 and unchanged house/navigation."""
from pathlib import Path
import json,hashlib,subprocess,sys,re
import numpy as np
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent;KIT=ROOT/'assets/farm/art';QA=ROOT/'output/homestead-439';QA.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
spec=json.loads((SRC/'asset_stats.json').read_text());report={'checks':[],'assets':{},'author':'赵云'}
def check(ok,label):
 report['checks'].append({'passed':bool(ok),'check':label})
 if not ok:print('FAIL',label)
def clip(poly,axis,limit,keep_positive):
 result=[]
 for i,a in enumerate(poly):
  b=poly[(i+1)%len(poly)];da=(a[axis]-limit)*(1 if keep_positive else -1);db=(b[axis]-limit)*(1 if keep_positive else -1)
  if da>=0:result.append(a)
  if (da>=0)!=(db>=0):result.append(a+(b-a)*da/(da-db))
 return result
palette=np.array([[int(h[i:i+2],16)/255 for i in [0,2,4]] for h in spec['palette_srgb'].values()]);palette=np.where(palette<=.04045,palette/12.92,((palette+.055)/1.055)**2.4)
for name,e in spec['assets'].items():
 path=KIT/(name+'.glb');d,b=load_glb(path);m=d['meshes'][0];p=m['primitives'][0];x=np.array(accessor(d,b,p['attributes']['POSITION']));n=np.array(accessor(d,b,p['attributes']['NORMAL']));c=np.array(accessor(d,b,p['attributes']['COLOR_0']));ids=np.array(accessor(d,b,p['indices'])).reshape(-1,3)
 check(len(d['meshes'])==1 and len(m['primitives'])==1 and m['name']==name+'_mobile',name+': single mobile mesh / surface')
 check(len(d['nodes'])==1 and d['nodes'][0]=={'mesh':0,'name':name},name+': identity root at the shared house anchor')
 check(not any(d.get(k) for k in ['skins','animations','textures','images','cameras']) and 'KHR_lights_punctual' not in d.get('extensions',{}),name+': no lights, cameras, rig, animation or bitmap')
 check(len(ids)==e['triangles'] and len(ids)<=1500,name+': actual triangle budget')
 check(np.isfinite(x).all() and np.isfinite(n).all() and np.isfinite(c).all(),name+': finite attributes')
 check(np.allclose([x.min(0),x.max(0)],e['bounds'],atol=1e-6) and abs(x[:,1].min())<1e-6,name+': grounded and recorded bounds')
 check(np.allclose(np.linalg.norm(n,axis=1),1,atol=1e-4),name+': unit normals')
 cross=np.cross(x[ids[:,1]]-x[ids[:,0]],x[ids[:,2]]-x[ids[:,0]])
 check(np.all(np.linalg.norm(cross,axis=1)>1e-10) and np.all((cross*n[ids].mean(1)).sum(1)>0),name+': no degenerate or reversed shading faces')
 pbr=d['materials'][0]['pbrMetallicRoughness'];check(len(d['materials'])==1 and abs(pbr['roughnessFactor']-.9)<1e-6 and pbr['metallicFactor']==0,name+': farm matte material')
 scale=(c[:,:3]@palette.T)/(palette*palette).sum(1)
 error=np.linalg.norm(c[:,:3,None]-palette.T[None,:,:]*scale[:,None,:],axis=1)
 match=np.argmin(error,axis=1);rows=np.arange(len(c))
 check(np.all(error[rows,match]<2e-6) and np.all(scale[rows,match]>=.61999) and np.all(scale[rows,match]<=1.00001),name+': house/farm palette with only original 0.62–1 vertex AO factor')
 blocked=[]
 # Union includes the requested path and sign cells; low floor and >=2m roof are exempt.
 for i,tri in enumerate(x[ids]):
  if tri[:,2].max()<=.975 or tri[:,2].min()>=1.625 or tri[:,1].max()<=.05 or tri[:,1].min()>=2.0:continue
  poly=list(tri)
  for axis,lo,hi in [(0,-3.575,1.625),(1,.05001,1.99999),(2,.975001,1.624999)]:
   poly=clip(poly,axis,lo,True) if poly else [];poly=clip(poly,axis,hi,False) if poly else []
  if len(poly)>=3 and any(np.linalg.norm(np.cross(poly[j]-poly[0],poly[j+1]-poly[0]))>1e-9 for j in range(1,len(poly)-1)):blocked.append(i)
 check(not blocked,name+': protected row 14 has no fixtures between .05 and 2.0 m')
 if e['stage']=='porch':
  floor=x[(x[:,2]>.975)&(x[:,1]<.2)];check(len(floor)>0 and floor[:,1].max()<=.050001,name+': flat <=.05m new landing')
  overhead=x[(x[:,2]>.975)&(x[:,1]>.2)]
  if len(overhead):check(overhead[:,1].min()>=1.99999,name+': >=2m forward canopy clearance')
 text=(KIT/(name+'.glb.import')).read_text();uid=re.search(r'^uid="(uid://[^"]+)"$',text,re.M)
 check(uid is not None and all(s in text.splitlines() for s in ['nodes/root_script=null','gltf/texture_map_mode=1','meshes/light_baking=1','meshes/generate_lods=false','meshes/create_shadow_meshes=true']),name+': generated UID and complete import settings')
 digest=hashlib.sha256(path.read_bytes()).hexdigest();check(digest==e['sha256'],name+': export SHA matches stats')
 report['assets'][name]={'triangles':len(ids),'surfaces':1,'sha256':digest,'uid':uid.group(1) if uid else None,'bounds':e['bounds'],'blocked_row14_triangles':blocked}
base_ref=subprocess.check_output(['git','merge-base','HEAD','origin/wp-3d-scene'],cwd=ROOT,text=True).strip()
base=json.loads(subprocess.check_output(['git','show',base_ref+':assets/farm/art/manifest.json'],cwd=ROOT));current=json.loads((KIT/'manifest.json').read_text())
mutable=set(spec['assets'])|{'master_farmhouse_a','master_farmhouse_b'}
check(all(current['assets'].get(k)==v for k,v in base['assets'].items() if k not in mutable) and list(current['assets'])[:len(base['assets'])]==list(base['assets']),'farm manifest retains all prior entries and order')
check(hashlib.sha256((KIT/'house_cottage.glb').read_bytes()).hexdigest()==spec['house_sha256'],'original cottage unchanged')
check(not subprocess.check_output(['git','diff',base_ref,'--name-only','--','modules','scenes'],cwd=ROOT,text=True),'no game code / navigation edits')
report['triangles_total']=sum(e['triangles'] for e in report['assets'].values());report['passed']=all(c['passed'] for c in report['checks']);(QA/'asset-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('HOMESTEAD_GEOMETRY',report['passed'],len(report['checks']),report['triangles_total'],'triangles');raise SystemExit(0 if report['passed'] else 1)
