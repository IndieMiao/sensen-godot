from pathlib import Path
import sys,json,hashlib,subprocess,collections,numpy as np
from PIL import Image
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/museum-far-roof-424';KIT=ROOT/'assets/landmarks/alcatraz_island'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
ref=json.loads((SRC/'provenance.json').read_text());contract=json.loads((SRC/'contract.json').read_text());m=json.loads((KIT/'alc_museum_far_manifest.json').read_text());checks=[]
def check(ok,label,evidence=None):checks.append({'check':label,'passed':bool(ok),'evidence':evidence})
def read(path):
 d,b=load_glb(path);p=d['meshes'][0]['primitives'][0]
 return d,np.array(accessor(d,b,p['attributes']['POSITION'])),np.array(accessor(d,b,p['attributes']['NORMAL'])),np.array(accessor(d,b,p['attributes']['COLOR_0'])),np.array(accessor(d,b,p['indices'])).reshape(-1,3)
nd,nv,nn,nc,ni=read(KIT/'alc_museum.glb');fd,fv,fn,fc,fi=read(KIT/'alc_museum_far.glb');od,ov,on,oc,oi=read(OUT/'baseline_alc_museum_far.glb')
def signature(v,n,c,t):return tuple(sorted(tuple(np.concatenate([v[i],n[i],c[i]]).round(5)) for i in t))
def groups(v,ix):
 keys={};parent=[];ids=[]
 for point in v:
  key=tuple(point.round(5))
  if key not in keys:keys[key]=len(keys);parent.append(len(parent))
  ids.append(keys[key])
 def root(a):
  while a!=parent[a]:parent[a]=parent[parent[a]];a=parent[a]
  return a
 for a,b,c in ix:
  ra=root(ids[a]);parent[root(ids[b])]=ra;parent[root(ids[c])]=ra
 out=collections.defaultdict(list)
 for t in ix:out[root(ids[t[0]])].append(t)
 return out.values()
check(hashlib.sha256((KIT/'alc_museum.glb').read_bytes()).hexdigest()==ref['near_sha256']==contract['stats']['sha256'],'Pinned ebce1cec near GLB unchanged')
check(hashlib.sha256((KIT/'alc_museum_far.glb.import').read_bytes()).hexdigest()==ref['far_import_sha256'],'Far .import and UID byte-identical')
check(hashlib.sha256((KIT/'alc_museum_far.glb').read_bytes()).hexdigest()==m['sha256'],'Far manifest digest')
check(len(fi)==m['triangles']==2239 and len(ni)==8757,'Measured triangle counts',[len(ni),len(oi),len(fi)])
check(len(fi)-len(oi)==34,'Only34 extra triangles',100*(len(fi)/len(oi)-1))
check(len(fd['meshes'])==1 and len(fd['meshes'][0]['primitives'])==1 and len(fd['materials'])==1,'One mesh/surface/material')
check(fd['meshes'][0]['name']=='alc_museum_far_mobile','Mesh name retained')
check(not fd.get('images') and not fd.get('textures') and not fd.get('skins') and not fd.get('animations') and not fd.get('cameras'),'No texture/skin/animation/camera')
check(all(n.get('translation',[0,0,0])==[0,0,0] and n.get('scale',[1,1,1])==[1,1,1] for n in fd['nodes']),'Original local pivot/unit scale')
check(np.allclose([nv.min(0),nv.max(0)],[fv.min(0),fv.max(0)],atol=2e-6),'Near/far actual AABB match including enlarged vents',[fv.min(0).tolist(),fv.max(0).tolist()])
check(abs(fv[:,1].max()-9.18)<1e-6,'Vent top at9.18m')
t=fv[fi];cross=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);check((np.linalg.norm(cross,axis=1)>1e-10).all(),'No degenerate triangles')
check((np.sum(cross*fn[fi].mean(1),axis=1)>-1e-8).all(),'Winding agrees with outward normals')
check(np.allclose(np.linalg.norm(fn,axis=1),1,atol=.001),'Unit normals')
old_nonroof=[]
for ts in groups(ov,oi):
 if ov[np.unique(ts),1].min()<8.37:old_nonroof.extend(ts)
expected=collections.Counter(signature(ov,on,oc,t) for t in old_nonroof);actual=collections.Counter(signature(fv,fn,fc,t) for t in fi)
missing=expected-actual
check(not missing and len(old_nonroof)==1941,'All1941 previous non-roof triangles retain positions/normals/colours, including pictogram',{'missing':sum(missing.values())})
def linear(h):
 a=np.array(list(bytes.fromhex(h)))/255
 return np.where(a<=.04045,a/12.92,((a+.055)/1.055)**2.4)
for role,h in contract['colors_srgb'].items():
 col=linear(h);mask=np.linalg.norm(fc[:,:3]-col,axis=1)<.0001
 check(mask.any(),'Far uses exact '+role+' #'+h,int(mask.sum()))
 check((np.linalg.norm(nc[:,:3]-col,axis=1)<.0001).any(),'Near verifies '+role+' #'+h)
for i,sk in enumerate(contract['skylights'],1):
 x,z=sk['centre_xz'];mask=(abs(fv[:,1]-8.704)<1e-5)&(abs(fv[:,0]-x)<2)&(abs(fv[:,2]-z)<1.1)
 bounds=[fv[mask].min(0),fv[mask].max(0)]
 check(np.allclose(np.array(bounds).mean(0)[[0,2]],[x,z]) and np.allclose(np.ptp(fv[mask][:,[0,2]],axis=0),sk['curb_size_xz'],atol=1e-5),'Flat skylight'+str(i)+' centre/base dimensions',[b.tolist() for b in bounds])
for i,v in enumerate(contract['vents'],1):
 x,z=v['centre_xz']
 for key,cy,size in [('body',v['body_center_y'],v['body_size_xyz']),('cap',v['cap_center_y'],v['cap_size_xyz'])]:
  at=np.array([x,cy,z]);size=np.array(size);lo,hi=at-size/2,at+size/2
  corners=np.array([[a,b,c] for a in [lo[0],hi[0]] for b in [lo[1],hi[1]] for c in [lo[2],hi[2]]])
  check(all(np.max(abs(fv-p),axis=1).min()<3e-6 for p in corners),'Vent'+str(i)+' '+key+' exact measured envelope',size.tolist())
global_now=json.loads((KIT/'manifest.json').read_text());global_old=json.loads((SRC/'reference/manifest.json').read_text())
global_now['assets'].pop('alc_museum_far');global_old['assets'].pop('alc_museum_far');check(global_now==global_old,'Global manifest only updates far museum entry')
check(m['lod']=={'near':'alc_museum','far':'alc_museum_far','switch_distance_m':55,'margin_m':0},'55m LOD contract retained')
comparisons={}
for mode in ['full','front','mobile_wide','mobile_default','fixed']:
 a=OUT/'captures'/(mode+('_near' if mode=='fixed' else '_54m')+'.png');b=OUT/'captures'/(mode+('_far' if mode=='fixed' else '_56m')+'.png')
 if not a.exists() or not b.exists():continue
 aa=np.array(Image.open(a).convert('RGB'));bb=np.array(Image.open(b).convert('RGB'));delta=abs(aa.astype(float)-bb.astype(float));mask=np.any(aa!=aa[0,0],axis=2)|np.any(bb!=bb[0,0],axis=2)
 comparisons[mode]={'object_mean_rgb_255':float(delta[mask].mean()),'pixels_changed_gt12':int((delta.max(2)>12).sum()),'object_pixels':int(mask.sum()),'max_channel_255':float(delta.max())}
result={'author':'黄忠','virtual_user_id':m['virtual_user_id'],'parent_head':ref['parent_head'],'checks':checks,'passed':all(x['passed'] for x in checks),'comparisons':comparisons,'limitation':'Flat skylight panels intentionally omit near raised silhouette; pane normals match near slopes for lighting. Raster differences are reported, not asserted identical.'}
(OUT/'geometry-validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('ROOF_VERIFY',result['passed'],len(checks),comparisons)
if not result['passed']:sys.exit(1)
