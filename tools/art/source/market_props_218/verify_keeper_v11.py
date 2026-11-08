"""Compare the accepted keeper against v1.1; raytrace actual exported triangles."""
from pathlib import Path
import json,sys,argparse,subprocess,hashlib,collections,math
import numpy as np
ROOT=Path(__file__).resolve().parents[4];KIT=ROOT/'assets/rooms/market_plaza';sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();a.out.mkdir(parents=True,exist_ok=True)
base='288b47b94f966981603b3d132552d6b16f923303'
old=a.out/'keeper_before.glb';old.write_bytes(subprocess.check_output(['git','show',base+':assets/rooms/market_plaza/stall_keeper.glb'],cwd=ROOT))
def read(p):
 d,b=load_glb(p);pr=d['meshes'][0]['primitives'][0]
 v=np.array(accessor(d,b,pr['attributes']['POSITION']));c=np.array(accessor(d,b,pr['attributes']['COLOR_0']));i=np.array(accessor(d,b,pr['indices'])).reshape(-1,3)
 return d,v,c,i
before=read(old);after=read(KIT/'stall_keeper.glb');checks=[]
def check(ok,label,evidence=None):checks.append({'check':label,'passed':bool(ok),'evidence':evidence})
def signature(data):
 d,v,c,idx=data;out=collections.Counter()
 for tri in idx:
  if v[tri,1].max()>1.8:continue
  out[tuple(sorted(tuple(np.round(np.concatenate([v[i],c[i]]),6)) for i in tri))]+=1
 return out
sb,sa=signature(before),signature(after)
check(sb==sa,'All triangles entirely below1.8m retain position/colour',{'before':sum(sb.values()),'after':sum(sa.values())})
_,v,c,idx=after
check(np.allclose(np.ptp(v,axis=0),[3.2,3.1,1.6],atol=1e-6),'Measured3.2x1.6x3.1m envelope')
check(len(idx)<=2500,'Keeper triangle budget',len(idx))
check(set(tuple(np.round(x,6)) for x in before[2])==set(tuple(np.round(x,6)) for x in c),'Palette unchanged')
# Cloth can be selected by its original sRGB colours, converted to linear.
def linear(h):
 c=np.array(list(bytes.fromhex(h)))/255;return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)
cloth=(np.linalg.norm(c[:,:3]-linear('91A680'),axis=1)<1e-4)|(np.linalg.norm(c[:,:3]-linear('F1E8D5'),axis=1)<1e-4)
front=v[cloth & (v[:,2]>.7679)];back=v[cloth & (v[:,2]<-.7679)]
check(front[:,1].min()>=2.8,'Front scallop lower edge>=2.8m',float(front[:,1].min()))
check(back[:,1].min()>=2.3,'Rear scallop lower edge>=2.3m',float(back[:,1].min()))
check(abs(v[:,1].max()-3.1)<1e-6,'Overall highest point3.10m')
# Full model ray intersections, no canopy approximation / bounding-box shortcut.
def intersect(vertices,indices,origin,direction):
 t=vertices[indices];e1=t[:,1]-t[:,0];e2=t[:,2]-t[:,0];p=np.cross(np.broadcast_to(direction,e2.shape),e2);det=np.einsum('ij,ij->i',e1,p)
 valid=np.abs(det)>1e-9;inv=np.zeros_like(det);inv[valid]=1/det[valid];off=origin-t[:,0];u=np.einsum('ij,ij->i',off,p)*inv;q=np.cross(off,e1);vv=q@direction*inv;distance=np.einsum('ij,ij->i',e2,q)*inv
 return int(np.sum(valid&(u>=0)&(vv>=0)&(u+vv<=1)&(distance>1e-6)))
pitch=math.radians(33);direction=np.array([0,math.sin(pitch),math.cos(pitch)]);z=-.45*math.sqrt(2);rays=[]
for height in [1.6,1.8,1.9,1.95,2.0]:
 for x in [-.18,0,.18]:
  origin=np.array([x,height-.05,z]);hits={name:intersect(data[1],data[3],origin,direction) for name,data in [('before',before),('after',after)]}
  rays.append({'world_head_height_m':height,'local_origin':origin.tolist(),'hits':hits})
check(all(r['hits']['before']>0 for r in rays),'Baseline reproduces head occlusion',15)
check(all(r['hits']['after']==0 for r in rays),'All15 head region rays clear after change',rays)
unchanged=[]
for p in KIT.iterdir():
 if p.suffix in ['.glb','.import','.tres'] and p.name!='stall_keeper.glb':
  original=subprocess.check_output(['git','show',base+':'+str(p.relative_to(ROOT))],cwd=ROOT);check(p.read_bytes()==original,p.name+' unchanged');unchanged.append(p.name)
report={'baseline':base,'option':'A front-high sloping canopy','checks':checks,'rays':rays,'unchanged_files':unchanged,'passed':all(x['passed'] for x in checks),'sha256':hashlib.sha256((KIT/'stall_keeper.glb').read_bytes()).hexdigest()}
(a.out/'keeper-validation.json').write_text(json.dumps(report,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('KEEPER_AUDIT',report['passed'],len(checks));raise SystemExit(0 if report['passed'] else 1)
