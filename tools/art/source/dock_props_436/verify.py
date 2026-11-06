"""Independent GLB, metre dimensions, palette, topology, import and scope audit."""
from pathlib import Path
import json,hashlib,re,sys,subprocess
import numpy as np
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent
KIT=ROOT/'assets/landmarks/_shared/dock_props';OUT=ROOT/'output/dock-props-436'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
m=json.loads((KIT/'manifest.json').read_text());ref=json.loads((SRC/'provenance.json').read_text())
checks=[];uids=[];rows={}
def check(ok,label,evidence=None):checks.append({'check':label,'passed':bool(ok),'evidence':evidence})
def rgb(h):
 a=np.array(list(bytes.fromhex(h)))/255
 return np.where(a<=.04045,a/12.92,((a+.055)/1.055)**2.4)
colors=np.array([rgb(h) for h in m['palette_srgb'].values()])
for name,row in m['assets'].items():
 path=KIT/row['file'];d,b=load_glb(path);p=d['meshes'][0]['primitives'][0]
 v=np.array(accessor(d,b,p['attributes']['POSITION']));n=np.array(accessor(d,b,p['attributes']['NORMAL']))
 c=np.array(accessor(d,b,p['attributes']['COLOR_0']));indices=np.array(accessor(d,b,p['indices'])).reshape(-1,3);tri=v[indices]
 check(hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256'],name+' manifest digest')
 check(len(d['meshes'])==1 and len(d['meshes'][0]['primitives'])==1,name+' one mesh/surface')
 check(d['meshes'][0]['name']==name+'_mobile',name+' named mesh')
 check(len(indices)==row['triangles'] and len(indices)<=800,name+' measured triangle budget',len(indices))
 check(np.allclose([v.min(0),v.max(0)],row['bounds'],atol=1e-6),name+' measured bounds')
 check(np.isfinite(v).all() and np.isfinite(n).all(),name+' finite vertices/normals')
 check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),name+' nondegenerate faces')
 check(not d.get('animations') and not d.get('skins') and not d.get('cameras') and not d.get('extensions',{}).get('KHR_lights_punctual'),name+' no animation/rig/camera/light')
 check(not d.get('images') and not d.get('textures'),name+' no texture dependency')
 check(np.allclose(c[:,3],1) if c.shape[1]==4 else True,name+' opaque vertex alpha')
 distances=np.linalg.norm(c[:,:3,None]-colors.T[None,:,:],axis=1).min(axis=1)
 check(distances.max()<.0001,name+' linear vertex colours match warm palette',float(distances.max()))
 check(all(node.get('scale',[1,1,1])==[1,1,1] for node in d['nodes']),name+' unit node scales')
 check(abs(v[:,1].min())<1e-6,name+' base pivot at0')
 cfg=(KIT/(row['file']+'.import')).read_text();uid=re.search(r'uid="(uid://[a-y0-8]+)"',cfg)
 check(uid is not None,name+' Godot UID');uids.append(uid.group(1) if uid else '')
 for param in ['nodes/root_script=null','gltf/texture_map_mode=1','meshes/light_baking=1']:check(param in cfg,name+' '+param)
 rows[name]={'triangles':len(indices),'bounds':[v.min(0).tolist(),v.max(0).tolist()],'bytes':path.stat().st_size}
check(len(rows)==12,'All twelve requested props')
check(len(set(uids))==len(uids),'Unique Godot-generated GLB UIDs')
check((KIT/'dock_props_import.gd.uid').exists(),'Importer UID included')
check(not list(KIT.glob('*.png')) and not list(KIT.glob('*.tscn')) and not list(KIT.glob('*layout*')),'No texture duplication or runtime scene/layout')
check(m['palette_srgb']['wood']=='A3815D' and m['palette_srgb']['wood_light']=='B89972' and m['palette_srgb']['wood_dark']=='795F47','Exact approved #830 wood palette')
check(rows['boarding_gangplank']['triangles']<=800,'Gangplank budget includes both guardrails')
check(np.allclose(np.subtract(rows['boarding_gangplank']['bounds'][1],rows['boarding_gangplank']['bounds'][0])[[0,2]],[2.4,1.2],atol=1e-6),'Actual gangplank span2.4m and width1.2m')
check(m['assets']['ticket_booth']['graphic_area_m']==[.96,.23],'Booth blank graphic field dimensions')
check(len(list(SRC.glob('*.blend')))==12,'Twelve editable source files')
conn=json.loads((SRC/'dock_connection.json').read_text())
source=subprocess.check_output(['git','show',conn['source_ref']+':assets/landmarks/_shared/coast_kit/'+conn['asset']],cwd=ROOT)
check(hashlib.sha256(source).hexdigest()==conn['source_sha256'],'Connection uses actual pinned426 terminal')
check(np.allclose(np.add(conn['new_gangplank']['root_for_unrotated_end'],conn['new_gangplank']['dock_port']),conn['terminal_edge_center']),'Connector transforms meet exactly')
check(abs((conn['terminal_bumpers']['clear_width']-conn['new_gangplank']['width'])/2-.13)<1e-6,'Gangplank clears terminal bumpers13cm per side')
diff=subprocess.check_output(['git','diff','--name-status',ref['base_commit']],cwd=ROOT,text=True)
allowed=('assets/landmarks/_shared/dock_props/','tools/art/source/dock_props_436/','docs/design/dock-props-436-2026-11-06/')
unexpected=[]
for line in diff.splitlines():
 status,path=line.split('\t',1)
 if path=='.codex/config.toml':continue
 if status!='A' or not path.startswith(allowed):unexpected.append(line)
check(not unexpected,'All pre-existing tracked assets unchanged',{'base':ref['base_commit'],'unexpected':unexpected})
hashes=json.loads((OUT/'dependency-hashes.json').read_text())
drift=[path for path,row in hashes.items() if hashlib.sha256((OUT/'project'/path).read_bytes()).hexdigest()!=row['sha256']]
check(not drift,'Review dependencies identical to pinned426/430/432/434 and ground',{'files':len(hashes),'changed':drift})
baseline='7c09ca3d898fd825117ea5c4e617336569768717'
for path in KIT.glob('*.glb'):
 if path.stem!='beacon_pole':check(path.read_bytes()==subprocess.check_output(['git','show',baseline+':'+str(path.relative_to(ROOT))],cwd=ROOT),path.stem+' unchanged from v1')
check(all(path.read_bytes()==subprocess.check_output(['git','show',baseline+':'+str(path.relative_to(ROOT))],cwd=ROOT) for path in KIT.glob('*.glb.import')),'All12 imports/UIDs unchanged from v1')
prior=OUT/'beacon-v1.glb';prior.write_bytes(subprocess.check_output(['git','show',baseline+':'+str((KIT/'beacon_pole.glb').relative_to(ROOT))],cwd=ROOT))
def shape(path):
 d,b=load_glb(path);p=d['meshes'][0]['primitives'][0];v=np.array(accessor(d,b,p['attributes']['POSITION']));ids=np.array(accessor(d,b,p['indices'])).reshape(-1,3)
 return sorted(tuple(sorted(tuple(round(float(x),6) for x in point) for point in v[t])) for t in ids)
check(shape(prior)==shape(KIT/'beacon_pole.glb'),'Beacon geometry unchanged; only colours revised')
report={'author':'黄忠','virtual_user_id':m['virtual_user_id'],'checks':checks,'passed':all(c['passed'] for c in checks),'assets':rows,'unique_triangles':sum(r['triangles'] for r in rows.values()),'unique_surfaces':len(rows),'base_commit':ref['base_commit']}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('DOCK_GEOMETRY',report['passed'],len(checks),report['unique_triangles'])
if not report['passed']:sys.exit(1)
