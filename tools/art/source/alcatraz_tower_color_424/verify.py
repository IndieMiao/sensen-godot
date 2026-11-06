from pathlib import Path
import json,hashlib,struct,subprocess,sys,collections,numpy as np
from PIL import Image
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/landmarks/alcatraz_island';OUT=ROOT/'output/alcatraz-tower-color-424';M=json.loads((SRC/'colour-map.json').read_text())
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
checks=[]
def check(ok,label,evidence=None):checks.append({'check':label,'passed':bool(ok),'evidence':evidence})
def old(rel):return subprocess.check_output(['git','show',M['base']+':'+rel],cwd=ROOT)
for name,row in M['assets'].items():
 path=KIT/(name+'.glb');base=old(str(path.relative_to(ROOT)));now=path.read_bytes();n=struct.unpack_from('<I',base,12)[0];doc=json.loads(base[20:20+n]);b0=base[28+n:];b1=now[28+n:]
 check(len(base)==len(now) and base[:28+n]==now[:28+n],name+' GLB JSON/header unchanged')
 mask=np.zeros(len(b0),dtype=bool)
 for mesh in doc['meshes']:
  for p in mesh['primitives']:
   a=doc['accessors'][p['attributes']['COLOR_0']];v=doc['bufferViews'][a['bufferView']];w={'VEC3':3,'VEC4':4}[a['type']];size={5121:1,5123:2,5126:4}[a['componentType']];start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',w*size)
   for i in range(a['count']):mask[start+i*stride:start+i*stride+3*size]=True
   pos0=np.array(accessor(doc,b0,p['attributes']['POSITION']));pos1=np.array(accessor(doc,b1,p['attributes']['POSITION']))
   check(np.array_equal(pos0,pos1),name+' positions exactly unchanged')
   check(accessor(doc,b0,p['indices'])==accessor(doc,b1,p['indices']),name+' topology unchanged')
   check(accessor(doc,b0,p['attributes']['NORMAL'])==accessor(doc,b1,p['attributes']['NORMAL']),name+' normals unchanged')
   c=np.array(accessor(doc,b1,p['attributes']['COLOR_0']));check(np.isfinite(c).all() and (c>=0).all() and (c<=1).all(),name+' valid colour values')
   check(len(doc['meshes'])==1 and len(mesh['primitives'])==1,name+' one mesh/surface')
 check(np.array_equal(np.frombuffer(b0,dtype=np.uint8)[~mask],np.frombuffer(b1,dtype=np.uint8)[~mask]),name+' ALL non-RGB buffer bytes unchanged (incl alpha)')
 check(not np.array_equal(np.frombuffer(b0,dtype=np.uint8)[mask],np.frombuffer(b1,dtype=np.uint8)[mask]),name+' colour actually changed')
 cfg=KIT/(name+'.glb.import');check(cfg.read_bytes()==old(str(cfg.relative_to(ROOT))),name+' import+UID byte-identical')
 check(hashlib.sha256(now).hexdigest()==row['sha256'],name+' manifest digest')
# Same semantic colour maps in both LODs; ensure exactly matching encoded palette values.
for name in ['alc_lighthouse','alc_watertower']:
 def colours(n):
  d,b=load_glb(KIT/(n+'.glb'));p=d['meshes'][0]['primitives'][0];return set(map(tuple,accessor(d,b,p['attributes']['COLOR_0'])))
 a=colours(name);b=colours(name+'_far');check(b<=a,name+' far palette is exact subset of near palette')
# Original three scenic cards stay byte-identical.
for name in ['alc_far_bridge','alc_far_city','alc_far_hills']:
 for ext in ['.glb','.glb.import']:
  path=KIT/(name+ext);check(path.read_bytes()==old(str(path.relative_to(ROOT))),name+ext+' unchanged')
# Prove the before/after screen only changes the towers, not the environment.
r=json.loads((OUT/'captures/godot-validation.json').read_text());before=np.array(Image.open(OUT/'captures/summit_before.png').convert('RGB'));after=np.array(Image.open(OUT/'captures/summit_after.png').convert('RGB'));delta=np.abs(before.astype(int)-after.astype(int));mask=np.zeros(before.shape[:2],dtype=bool)
for x0,y0,x1,y1 in r['tower_rects'].values():mask[max(0,int(y0)-3):min(mask.shape[0],int(y1)+4),max(0,int(x0)-3):min(mask.shape[1],int(x1)+4)]=True
outside=delta[~mask];check(int(outside.max())==0,'Identical world/camera/water outside tower bounding regions',int(outside.max()))
check(int(delta.max())>5,'Rendered colour change is visible',int(delta.max()))
# Museum sign increment: preserve all previously accepted far triangles outside lettering/icon.
def data(path):
 d,b=load_glb(path);p=d['meshes'][0]['primitives'][0];return [np.array(accessor(d,b,p['attributes'][k])) for k in ['POSITION','NORMAL','COLOR_0']]+[np.array(accessor(d,b,p['indices'])).reshape(-1,3)]
basepath=OUT/'museum_far_approved.glb';basepath.write_bytes(old('assets/landmarks/alcatraz_island/alc_museum_far.glb'));ov,on,oc,oi=data(basepath);nv,nn,nc,ni=data(KIT/'alc_museum_far.glb')
def split(v,n,c,ix):
 outside=collections.Counter();sign=[]
 for t in ix:
  p=v[t];isin=bool((abs(p[:,0])<2.11).all() and (p[:,1]>3.79).all() and (p[:,1]<4.5).all() and (p[:,2]>5.185).all() and (p[:,2]<5.201).all())
  key=tuple(sorted(tuple(np.concatenate([v[i],n[i],c[i]]).round(5)) for i in t))
  if isin:sign.append(key)
  else:outside[key]+=1
 return outside,sign
base_out,letters=split(ov,on,oc,oi);new_out,icon=split(nv,nn,nc,ni)
check(base_out==new_out,'Museum far outside sign is exactly previous accepted geometry/normal/colour')
check(len(letters)==219 and len(icon)==7,'Replace219 front letter triangles with7 pictogram triangles',[len(letters),len(icon)])
ref=ROOT/'tools/art/source/alcatraz_museum_far_424/reference/alc_museum_bf0c31b1.glb';rv,rn,rc,ri=data(ref);_,near_icon=split(rv,rn,rc,ri)
check(collections.Counter(icon)==collections.Counter(near_icon),'Far pictogram exact match to bf0c31b1 near')
report={'author':'黄忠','virtual_user_id':M['virtual_user_id'],'base':M['base'],'host':M['host_ref'],'checks':checks,'passed':all(c['passed'] for c in checks),'colour_changes':M['changes'],'image_diff':{'outside_tower_max_rgb_255':int(outside.max()) if hasattr(outside,'max') else 0,'changed_pixels':int((delta.max(2)>0).sum()),'max_rgb_255':int(delta.max())}}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('TOWER_SIGN_VERIFY',report['passed'],len(checks))
if not report['passed']:sys.exit(1)
