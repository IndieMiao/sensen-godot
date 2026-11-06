"""Independent exported glTF, shape-key, placement and import audit."""
from pathlib import Path
import sys,json,hashlib,re,subprocess,struct,numpy as np
SRC=Path(__file__).resolve().parent;ROOT=SRC.parents[3];KIT=ROOT/'assets/landmarks/alcatraz_island';OUT=ROOT/'output/alcatraz-ferry-424'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
m=json.loads((KIT/'ferry_gull_manifest.json').read_text());checks=[];measured={}
def check(ok,label,evidence=None):checks.append({'check':label,'passed':bool(ok),'evidence':evidence})
def points(d,b,index):
 a=d['accessors'][index];width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
 result=np.array(accessor(d,b,index)) if 'bufferView' in a else np.zeros((a['count'],width))
 if 'sparse' in a:
  sp=a['sparse'];ind=sp['indices'];val=sp['values'];iv=d['bufferViews'][ind['bufferView']];vv=d['bufferViews'][val['bufferView']]
  kind={5121:'B',5123:'H',5125:'I'}[ind['componentType']];indices=struct.unpack_from('<'+kind*sp['count'],b,iv.get('byteOffset',0)+ind.get('byteOffset',0))
  values=np.array(struct.unpack_from('<'+'f'*(sp['count']*width),b,vv.get('byteOffset',0)+val.get('byteOffset',0))).reshape(-1,width)
  result[list(indices)]=values
 return result
for name,entry in m['assets'].items():
 f=KIT/entry['file'];d,b=load_glb(f);check(hashlib.sha256(f.read_bytes()).hexdigest()==entry['sha256'],name+' manifest hash')
 check(len(d['meshes'])==1,name+' exactly one mesh');mesh=d['meshes'][0];check(mesh['name']==name+'_mobile',name+' mesh name')
 check(len(mesh['primitives'])==1 and len(d['materials'])==1,name+' one surface/material')
 check(not d.get('images') and not d.get('textures') and not d.get('skins') and not d.get('animations') and not d.get('cameras'),name+' no textures/rig/animation/camera')
 check(not d.get('extensions',{}).get('KHR_lights_punctual'),name+' no lights')
 check(all(n.get('scale',[1,1,1])==[1,1,1] and n.get('translation',[0,0,0])==[0,0,0] and n.get('rotation',[0,0,0,1])==[0,0,0,1] for n in d['nodes']),name+' original local pivot/unit transforms')
 p=mesh['primitives'][0];vs=points(d,b,p['attributes']['POSITION']);ns=points(d,b,p['attributes']['NORMAL']);cs=points(d,b,p['attributes']['COLOR_0']);ix=points(d,b,p['indices']).astype(int).reshape(-1,3)
 check(len(ix)==entry['triangles'] and len(ix)<=(400 if name=='gull' else 6000),name+' triangle count/cap',len(ix))
 check(np.isfinite(vs).all() and np.isfinite(cs).all(),name+' finite geometry/colour')
 check((cs>=0).all() and (cs<=1).all(),name+' linear colour range')
 check(cs.shape[1]==3 or np.allclose(cs[:,3],1),name+' opaque vertex colour')
 check(np.allclose([vs.min(0),vs.max(0)],entry['bounds'],atol=1e-6),name+' actual bounds match')
 triangles=vs[ix];cross=np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]);check((np.linalg.norm(cross,axis=1)>1e-10).all(),name+' no degenerate faces')
 check((np.sum(cross*ns[ix].mean(1),axis=1)>=-1e-8).all(),name+' normals agree with winding')
 check(np.allclose(np.linalg.norm(ns,axis=1),1,atol=.001),name+' unit normals')
 cfg=(KIT/(entry['file']+'.import')).read_text();uid=re.search(r'uid="(uid://[a-y0-8]+)"',cfg);check(uid is not None,name+' valid Godot-generated UID')
 for setting in ['gltf/texture_map_mode=1','meshes/light_baking=1','import_script/path="res://assets/landmarks/alcatraz_island/ferry_gull_material_import.gd"']:check(setting in cfg,name+' '+setting)
 if name in ['ferry','gull']:
  old=subprocess.check_output(['git','show',m['host_ref']+':assets/landmarks/alcatraz_island/'+entry['file']+'.import'],cwd=ROOT).decode();check(uid and uid.group(0) in old,name+' preserve placeholder Godot UID')
 if name.startswith('ferry'):
  check(abs(np.ptp(vs,axis=0)[0]-25)<1e-5,name+' exactly 25m X length')
  check(abs(vs.min(0)[1]+1)<1e-6,name+' original waterline pivot / submerged -1m keel')
 else:
  names=mesh.get('extras',{}).get('targetNames',[]);check(names==['preen','spread'],name+' two named shape targets',names)
  check(len(p.get('targets',[]))==2,name+' exactly three static poses including basis')
  foot=vs[:,1]<.15
  for targetname,target in zip(names,p['targets']):
   delta=points(d,b,target['POSITION']);posed=vs+delta
   check(np.allclose(delta[foot],0,atol=1e-6),targetname+' feet/root unmoved')
   check(np.allclose([posed.min(0),posed.max(0)],entry['pose_bounds'][targetname],atol=1e-6),targetname+' pose bounds measured')
   check(np.isfinite(posed).all(),targetname+' finite')
   t=posed[ix];check((np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1)>1e-10).all(),targetname+' no collapsed triangles')
 measured[name]={'triangles':len(ix),'bounds':[vs.min(0).tolist(),vs.max(0).tolist()],'uid':uid.group(1) if uid else None}
layout=json.loads((SRC/'reference/layout-b16c3198.json').read_text());old=[p for p in layout['placements'] if p['asset'] in ['ferry','gull']]
check(m['placements']==old,'all four original placements / yaw / scale / collision fields identical')
check(not any(p['collision'] for p in m['placements']),'all decorative / noncolliding')
check(m['ferry_lod_group']['switch_distance_m']==55 and m['ferry_lod_group']['margin_m']==0,'55m hard LOD handoff')
check(m['assets']['ferry_far']['triangles']<=m['assets']['ferry']['triangles']*.3,'far <=30% near triangles')
check((KIT/'ferry_gull_material_import.gd.uid').exists(),'import script Godot UID delivered')
fixture=json.loads((OUT/'fixture.json').read_text())
for rel,digest in fixture['host_hashes'].items():check(hashlib.sha256((OUT/'project'/rel).read_bytes()).hexdigest()==digest,'review pinned host byte-identical '+rel)
report={'author':'黄忠','virtual_user_id':m['virtual_user_id'],'checks':checks,'measured':measured,'placed_near_triangles':m['assets']['ferry']['triangles']+3*m['assets']['gull']['triangles'],'placed_far_triangles':m['assets']['ferry_far']['triangles']+3*m['assets']['gull']['triangles'],'passed':all(x['passed'] for x in checks)}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('GEOMETRY',report['passed'],len(checks),measured)
if not report['passed']:sys.exit(1)
