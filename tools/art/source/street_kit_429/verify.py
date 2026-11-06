"""Independent GLB, metre dimensions, palette, topology, import and scope audit."""
from pathlib import Path
import json,hashlib,re,sys,subprocess
import numpy as np
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent
KIT=ROOT/'assets/landmarks/_shared/street_kit';OUT=ROOT/'output/street-kit-429'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
m=json.loads((KIT/'kit_manifest.json').read_text());ref=json.loads((SRC/'reference/provenance.json').read_text())
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
 check(np.ptp(v[:,0])<=2.001 and np.ptp(v[:,2])<=2.001,name+' fits2m placement cell')
 if name=='sign_wall':check(abs(v[:,1].max()+v[:,1].min())<1e-6 and abs(v[:,2].min())<1e-6,name+' rear-centre wall pivot')
 else:check(abs(v[:,1].min())<1e-6,name+' base pivot at0')
 if name in ['bench_wood','bench_stone','umbrella_table']:
  check(abs(v[v[:,1]<.8,1].max()-row['seat_height_m'])<1e-6,name+' actual seat height',float(v[v[:,1]<.8,1].max()))
 cfg=(KIT/(row['file']+'.import')).read_text();uid=re.search(r'uid="(uid://[a-y0-8]+)"',cfg)
 check(uid is not None,name+' Godot UID');uids.append(uid.group(1) if uid else '')
 for param in ['nodes/root_script=null','gltf/texture_map_mode=1','meshes/light_baking=1']:check(param in cfg,name+' '+param)
 rows[name]={'triangles':len(indices),'bounds':[v.min(0).tolist(),v.max(0).tolist()],'bytes':path.stat().st_size}
check(len(rows)==16,'All sixteen modules')
check(len(set(uids))==len(uids),'Unique generated GLB UIDs')
check((KIT/'street_kit_import.gd.uid').exists(),'Importer UID included')
check(not list(KIT.glob('*.png')) and not list(KIT.glob('*.tscn')) and not list(KIT.glob('*layout*')),'Kit has no image duplication or assembled runtime scene/layout')
check(abs(rows['railing_straight_2m']['bounds'][0][0]+1)<1e-6 and abs(rows['railing_straight_2m']['bounds'][1][0]-1)<1e-6,'Railing exactly2m endpoints')
corner=rows['railing_corner']['bounds'];check(abs(corner[1][0]-1)<1e-6 and abs(corner[1][2]-1)<1e-6,'Corner endpoints at1m on both axes')
# v1.2: measure the cloth separately from the stools, and the light cap separately
# from the dark shaft. Overall umbrella-table width includes its two unchanged stools.
for name in ['umbrella_table','bollard']:
 d,b=load_glb(KIT/(name+'.glb'));p=d['meshes'][0]['primitives'][0]
 v=np.array(accessor(d,b,p['attributes']['POSITION']));c=np.array(accessor(d,b,p['attributes']['COLOR_0']))[:,:3]
 if name=='umbrella_table':
  cloth=(np.linalg.norm(c-rgb('EFE7D4'),axis=1)<.0001)|(np.linalg.norm(c-rgb('8AAFA2'),axis=1)<.0001)
  check(abs(np.max(np.linalg.norm(v[cloth][:,[0,2]],axis=1))*2-1.6)<1e-6,'Canopy actual diameter1.6m')
  check(abs(v[cloth,1].max()-2.86)<1e-6,'Canopy height preserved at2.86m')
  for h in ['A3815D','B89972','795F47']:check((np.linalg.norm(c-rgb(h),axis=1)<.0001).any(),'Umbrella retains muted wood '+h)
 else:
  cap=v[np.linalg.norm(c-rgb('F0E1C2'),axis=1)<.0001]
  check(np.allclose(np.ptp(cap,axis=0),[.28,.12,.28],atol=1e-6),'Bollard cream stone cap measured28x12x28cm')
  check(abs(cap[:,1].min()-.61)<1e-6 and abs(cap[:,1].max()-.73)<1e-6,'Cap is at the top of73cm bollard')
baseline='f842e3feffb76e17149f0857364f439bbd232e0b'
for path in KIT.glob('*.glb'):
 if path.stem not in ['umbrella_table','bollard']:
  check(path.read_bytes()==subprocess.check_output(['git','show',baseline+':'+str(path.relative_to(ROOT))],cwd=ROOT),path.stem+' unchanged from v1.1')
check(all(path.read_bytes()==subprocess.check_output(['git','show',baseline+':'+str(path.relative_to(ROOT))],cwd=ROOT) for path in KIT.glob('*.glb.import')),'All16 imports/UIDs byte-identical to v1.1')
# Comparing all tracked original files to the branch base prevents unrelated art edits.
diff=subprocess.check_output(['git','diff','--name-status',ref['base_commit']],cwd=ROOT,text=True)
allowed=('assets/landmarks/_shared/street_kit/','tools/art/source/street_kit_429/','docs/design/street-kit-429-2026-11-06/')
unexpected=[]
for line in diff.splitlines():
 status,path=line.split('\t',1)
 if path=='.codex/config.toml':continue
 if status!='A' or not path.startswith(allowed):unexpected.append(line)
check(not unexpected,'No original tracked files changed, including Alcatraz/Grace',{'base':ref['base_commit'],'unexpected':unexpected})
ground=json.loads((OUT/'ground-fixture-hashes.json').read_text())
check(all(hashlib.sha256((OUT/'project'/f).read_bytes()).hexdigest()==h for f,h in ground['files'].items()),'Review ground fixture byte-identical to #830',{'commit':ground['commit'],'files':len(ground['files'])})
report={'author':'黄忠','virtual_user_id':m['virtual_user_id'],'checks':checks,'passed':all(c['passed'] for c in checks),'assets':rows,'unique_triangles':sum(r['triangles'] for r in rows.values()),'unique_surfaces':len(rows),'base_commit':ref['base_commit']}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('STREET_GEOMETRY',report['passed'],len(checks),report['unique_triangles'])
if not report['passed']:sys.exit(1)
