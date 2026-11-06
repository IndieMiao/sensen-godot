"""Independent GLB diff + sparse morph checks; old hulls and old poses preserved."""
from pathlib import Path
import sys,json,hashlib,struct,re,subprocess,collections,numpy as np
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/landmarks/alcatraz_island';OUT=ROOT/'output/alcatraz-anim-424';BASE='996528d3a273d773e1e2168361ac79a1da9f15c4'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
checks=[]
def check(ok,label,evidence=None):checks.append({'check':label,'passed':bool(ok),'evidence':evidence})
def arr(d,b,index):
 a=d['accessors'][index];w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];r=np.array(accessor(d,b,index)) if 'bufferView' in a else np.zeros((a['count'],w))
 if 'sparse' in a:
  sp=a['sparse'];ind=sp['indices'];val=sp['values'];iv=d['bufferViews'][ind['bufferView']];vv=d['bufferViews'][val['bufferView']];kind={5121:'B',5123:'H',5125:'I'}[ind['componentType']]
  ids=struct.unpack_from('<'+kind*sp['count'],b,iv.get('byteOffset',0)+ind.get('byteOffset',0));vals=np.array(struct.unpack_from('<'+'f'*(sp['count']*w),b,vv.get('byteOffset',0)+val.get('byteOffset',0))).reshape(-1,w);r[list(ids)]=vals
 return r
def read(p):
 d,b=load_glb(p);pr=d['meshes'][0]['primitives'][0];attrs={k:arr(d,b,i) for k,i in pr['attributes'].items()};ix=arr(d,b,pr['indices']).astype(int).reshape(-1,3);targets={name:{k:arr(d,b,i) for k,i in tar.items()} for name,tar in zip(d['meshes'][0].get('extras',{}).get('targetNames',[]),pr.get('targets',[]))};return d,attrs,ix,targets
for name in ['ferry','ferry_far']:
 for ext in ['.glb','.glb.import']:
  now=(KIT/(name+ext)).read_bytes();old=subprocess.check_output(['git','show',BASE+':assets/landmarks/alcatraz_island/'+name+ext],cwd=ROOT);check(now==old,name+ext+' accepted original byte-identical')
oldpath=OUT/'gull-v1.glb';oldpath.write_bytes(subprocess.check_output(['git','show',BASE+':assets/landmarks/alcatraz_island/gull.glb'],cwd=ROOT))
od,oa,oi,ot=read(oldpath);d,a,ix,targets=read(KIT/'gull.glb')
check(len(ix)==len(oi)==284,'Gull triangles unchanged at284')
check(len(d['meshes'])==1 and len(d['meshes'][0]['primitives'])==1,'Gull one mesh/surface')
check(list(targets)==['preen','spread','turn_head'],'Old two poses + turn_head')
# Export vertex order normally stable; require actual buffer values identical.
for key in ['POSITION','NORMAL','COLOR_0']:check(np.array_equal(oa[key],a[key]),'Gull original '+key+' values unchanged')
check(np.array_equal(oi,ix),'Gull original indices unchanged')
for name in ['preen','spread']:
 for key in ot[name]:check(np.array_equal(ot[name][key],targets[name][key]),'Original '+name+' '+key+' morph unchanged')
foot=a['POSITION'][:,1]<.15
for name,target in targets.items():
 check(np.allclose(target['POSITION'][foot],0,atol=1e-7),name+' foot vertices fixed')
 posed=a['POSITION']+target['POSITION'];tris=posed[ix];check((np.linalg.norm(np.cross(tris[:,1]-tris[:,0],tris[:,2]-tris[:,0]),axis=1)>1e-10).all(),name+' nondegenerate pose')
check(np.count_nonzero(np.linalg.norm(targets['turn_head']['POSITION'],axis=1)>1e-7)>20,'Turn head actually moves head vertices')
fd,fa,fi,ft=read(KIT/'ferry_flag.glb');check(len(fi)==52 and len(fd['meshes'][0]['primitives'])==1,'Flag52 triangles / one surface')
check(list(ft)==['flutter'],'Flag has one flutter target')
check(not fd.get('images') and not fd.get('skins') and not fd.get('animations'),'Flag no texture / rig / embedded animation')
check(abs(fa['POSITION'][:,1].min())<1e-7,'Flag pole-base origin grounded')
for weight in [0,0.5,1]:
 posed=fa['POSITION']+ft['flutter']['POSITION']*weight;t=posed[fi];check(np.isfinite(posed).all() and (np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1)>1e-10).all(),'Flag nondegenerate throughout flutter '+str(weight))
pole=fa['POSITION'][:,0]<.03;check(np.allclose(ft['flutter']['POSITION'][pole],0,atol=1e-7),'Flag pole/cloth root stationary')
check(np.max(abs(fa['POSITION'][:,2]))<=.03501 and np.max(abs((fa['POSITION']+ft['flutter']['POSITION'])[:,2]))<=.03501,'Flag depth sway <=3.5cm')
for name in ['gull','ferry_flag']:
 cfg=(KIT/(name+'.glb.import')).read_text();check(re.search('uid="uid://[a-y0-8]+"',cfg) is not None,name+' Godot UID')
 for s in ['nodes/root_script=null','gltf/texture_map_mode=1','meshes/light_baking=1']:check(s in cfg,name+' '+s)
 if name=='gull':
  old=subprocess.check_output(['git','show',BASE+':assets/landmarks/alcatraz_island/gull.glb.import'],cwd=ROOT).decode();check(re.search('uid="uid://[a-y0-8]+"',cfg).group(0) in old,'Gull UID preserved')
for name in ['gull.tscn','ferry.tscn','gull_animations.tres','ferry_animations.tres']:
 t=(KIT/name).read_text();check(re.search('uid="uid://[a-y0-8]+"',t) is not None,name+' native Godot UID')
 if name.endswith('tscn'):
  check('type="ArrayMesh"' not in t,name+' references original GLBs without embedded mesh copies')
  check('autoplay' not in t,name+' no autoplay property')
  check('type="Script"' not in t,name+' no runtime script dependency')
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','baseline':BASE,'checks':checks,'passed':all(x['passed'] for x in checks),'triangles':{'gull':284,'flag':52,'ferry_near_plus_flag':5196,'ferry_far_plus_flag':1532}}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('ANIM_GLTF_VERIFY',report['passed'],len(checks))
if not report['passed']:sys.exit(1)
