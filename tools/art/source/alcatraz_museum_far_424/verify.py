"""Independent decoded GLB geometry/colour and aligned-raster LOD comparison."""
from pathlib import Path
import sys,json,hashlib,re,subprocess,collections,numpy as np
from PIL import Image
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];OUT=ROOT/'output/alcatraz-museum-far-424';KIT=ROOT/'assets/landmarks/alcatraz_island'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
m=json.loads((KIT/'alc_museum_far_manifest.json').read_text());checks=[]
def check(ok,label,evidence=None):checks.append({'check':label,'passed':bool(ok),'evidence':evidence})
def read(path):
 d,b=load_glb(path);p=d['meshes'][0]['primitives'][0]
 return d,np.array(accessor(d,b,p['attributes']['POSITION'])),np.array(accessor(d,b,p['attributes']['NORMAL'])),np.array(accessor(d,b,p['attributes']['COLOR_0'])),np.array(accessor(d,b,p['indices'])).reshape(-1,3)
npath=SRC/m['near_source']['near_file'];fpath=KIT/m['file'];nd,nv,nn,nc,ni=read(npath);fd,fv,fn,fc,fi=read(fpath)
check(hashlib.sha256(npath.read_bytes()).hexdigest()==m['near_sha256'],'pinned near source hash')
check(hashlib.sha256(fpath.read_bytes()).hexdigest()==m['sha256'],'far manifest hash')
check(len(ni)==m['near_triangles'] and len(fi)==m['triangles'],'actual triangle counts',[len(ni),len(fi)])
check(.18<=len(fi)/len(ni)<=.30,'far around one quarter',len(fi)/len(ni))
check(len(fd['meshes'])==1 and len(fd['meshes'][0]['primitives'])==1 and len(fd['materials'])==1,'one mesh / surface / material')
check(fd['meshes'][0]['name']=='alc_museum_far_mobile','mesh name')
check(not fd.get('images') and not fd.get('textures') and not fd.get('skins') and not fd.get('animations') and not fd.get('cameras'),'no textures / bones / animation / cameras')
check(all(n.get('translation',[0,0,0])==[0,0,0] and n.get('scale',[1,1,1])==[1,1,1] and n.get('rotation',[0,0,0,1])==[0,0,0,1] for n in fd['nodes']),'identity local pivot/unit scale')
check(np.allclose([nv.min(0),nv.max(0)],[fv.min(0),fv.max(0)],atol=1e-6),'near/far identical measured envelope')
check(np.isfinite(fv).all() and np.isfinite(fc).all(),'finite positions/colour')
t=fv[fi];cross=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);check((np.linalg.norm(cross,axis=1)>1e-10).all(),'no degenerate triangles')
check((np.sum(cross*fn[fi].mean(1),axis=1)>-1e-8).all(),'outward normals agree with winding')
check(np.allclose(np.linalg.norm(fn,axis=1),1,atol=.001),'unit normals')
check(set(map(tuple,nc.round(4)))==set(map(tuple,fc.round(4))),'exact inherited near colour set')
# Non-window source triangles must remain, including custom normals and colours.
def signatures(v,n,c,ix):
 return collections.Counter(tuple(sorted(tuple(np.concatenate([v[i],n[i],c[i]]).round(5)) for i in tri)) for tri in ix)
near_other=[]
for tri in ni:
 p=nv[tri];is_window=bool((p[:,2]>5.009).all() and (p[:,2]<5.051).all() and any((p[:,0]>=w['near_bounds'][0][0]-1e-5).all() and (p[:,0]<=w['near_bounds'][1][0]+1e-5).all() and (p[:,1]>=w['near_bounds'][0][1]-1e-5).all() and (p[:,1]<=w['near_bounds'][1][1]+1e-5).all() for w in m['windows']))
 if not is_window:near_other.append(tri)
source=signatures(nv,nn,nc,near_other);target=signatures(fv,fn,fc,fi)
# Export quantization can alter normals in their last decimals; compare to 4dp if required.
missing=sum((source-target).values());check(missing==0,'every non-pane triangle retains positions/normals/colours',{'expected':len(near_other),'missing':missing})
check(len(m['windows'])==25,'retain all 25 window positions')
for w in m['windows']:
 lo,hi=np.array(w['near_bounds']);mask=(np.abs(fv[:,2]-w['front_z'])<1e-6)&(fv[:,0]>=lo[0]-1e-5)&(fv[:,0]<=hi[0]+1e-5)&(fv[:,1]>=lo[1]-1e-5)&(fv[:,1]<=hi[1]+1e-5)
 p=fv[mask];check(len(p)>=12 and np.allclose(p.min(0)[:2],lo[:2],atol=1e-6) and np.allclose(p.max(0)[:2],hi[:2],atol=1e-6),w['name']+' actual front placement and dimensions')
imported=(KIT/'alc_museum_far.glb.import').read_text();old=subprocess.check_output(['git','show','b16c3198:assets/landmarks/alcatraz_island/alc_museum_far.glb.import'],cwd=ROOT).decode()
uid=re.search(r'uid="uid://[a-y0-8]+"',imported);check(uid and uid.group(0) in old,'preserved placeholder Godot UID')
for line in ['nodes/root_script=null','gltf/texture_map_mode=1','meshes/light_baking=1']:check(line in imported,'import '+line)
check(m['placement']=={'position':[0,10,-13],'yaw_degrees':0,'scale':[1,1,1]},'original placement preserved')
comparisons={}
for name in ['full','front','mobile_wide','mobile_default','fixed']:
 a=OUT/'captures'/(name+('_near' if name=='fixed' else '_54m')+'.png');b=OUT/'captures'/(name+('_far' if name=='fixed' else '_56m')+'.png')
 if not a.exists() or not b.exists():continue
 aa=np.array(Image.open(a).convert('RGB'));bb=np.array(Image.open(b).convert('RGB'));diff=np.abs(aa.astype(float)-bb.astype(float));mask=np.any(aa!=aa[0,0],axis=2)|np.any(bb!=bb[0,0],axis=2)
 # Fullframe/raster measurements are evidence, not claims of absolute perceptual identity.
 comparisons[name]={'mean_rgb_255':float(diff.mean()),'object_mean_rgb_255':float(diff[mask].mean()) if mask.any() else 0,'pixels_changed_gt_12':int((diff.max(2)>12).sum()),'total_pixels':int(mask.size),'object_pixels':int(mask.sum()),'max_channel_255':float(diff.max())}
 check(comparisons[name]['object_mean_rgb_255']<1.0,name+' rendered near/far mean RGB difference <1/255',comparisons[name])
report={'author':'黄忠','virtual_user_id':m['virtual_user_id'],'revision':m['revision'],'checks':checks,'comparisons':comparisons,'source':m['near_source'],'passed':all(x['passed'] for x in checks)}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('MUSEUM_VERIFY',report['passed'],len(checks),json.dumps(comparisons))
if not report['passed']:sys.exit(1)
