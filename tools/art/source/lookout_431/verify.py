from pathlib import Path
import json,hashlib,re,sys,subprocess
import numpy as np
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent
KIT=ROOT/'assets/landmarks/_shared/street_kit';OUT=ROOT/'output/lookout-431'
sys.path.insert(0,str(ROOT/'tools/art'));from verify_chef_sign import load_glb,accessor
m=json.loads((KIT/'kit_manifest.json').read_text());ref=json.loads((SRC/'provenance.json').read_text())
names=m['extension_tasks']['SGODOT-431']['assets'];checks=[];uids=[];rows={}
def check(ok,label,evidence=None):checks.append({'check':label,'passed':bool(ok),'evidence':evidence})
def rgb(h):
 a=np.array(list(bytes.fromhex(h)))/255
 return np.where(a<=.04045,a/12.92,((a+.055)/1.055)**2.4)
palette=np.array([rgb(h) for h in m['palette_srgb'].values()])
for name in names:
 row=m['assets'][name];path=KIT/row['file'];d,b=load_glb(path);p=d['meshes'][0]['primitives'][0]
 v=np.array(accessor(d,b,p['attributes']['POSITION']));n=np.array(accessor(d,b,p['attributes']['NORMAL']));c=np.array(accessor(d,b,p['attributes']['COLOR_0']))
 ix=np.array(accessor(d,b,p['indices'])).reshape(-1,3);tri=v[ix]
 check(hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256'],name+' manifest hash')
 check(len(d['meshes'])==1 and len(d['meshes'][0]['primitives'])==1,name+' one mesh/surface')
 check(d['meshes'][0]['name']==name+'_mobile',name+' mesh name')
 check(len(ix)==row['triangles'] and len(ix)<=800,name+' actual triangle count/budget',len(ix))
 check(np.allclose([v.min(0),v.max(0)],row['bounds'],atol=1e-6),name+' actual bounds')
 check(np.isfinite(v).all() and np.isfinite(n).all(),name+' finite geometry/normals')
 check((np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-10).all(),name+' no degenerate faces')
 check(not d.get('images') and not d.get('textures'),name+' texture-free')
 check(not d.get('skins') and not d.get('animations') and not d.get('cameras') and not d.get('extensions',{}).get('KHR_lights_punctual'),name+' no rig/animation/camera/light')
 check(c.shape[1]==3 or np.allclose(c[:,3],1),name+' opaque vertex colours')
 delta=np.linalg.norm(c[:,:3,None]-palette.T[None,:,:],axis=1).min(axis=1)
 check(delta.max()<.0001,name+' existing warm palette in linear COLOR_0',float(delta.max()))
 check(abs(v[:,1].min())<1e-6,name+' bottom pivot atY0')
 check(np.ptp(v[:,0])<=2.001 and np.ptp(v[:,2])<=2.001,name+' within2m module')
 check(all(np.allclose(n.get('scale',[1,1,1]),[1,1,1]) for n in d['nodes']),name+' unit node scale')
 cfg=Path(str(path)+'.import').read_text();uid=re.search(r'uid="(uid://[a-y0-8]+)"',cfg)
 check(uid is not None,name+' Godot-generated UID')
 for token in ['nodes/root_script=null','gltf/texture_map_mode=1','meshes/light_baking=1']:check(token in cfg,name+' '+token)
 rows[name]={'triangles':len(ix),'bounds':[v.min(0).tolist(),v.max(0).tolist()],'dimensions_m':np.ptp(v,axis=0).tolist()}
 if name=='lookout_sheltered_bench':check(abs(v[v[:,1]<.8,1].max()-.715)<1e-6,name+' seat height0.715m')
 if name=='lookout_compass_disc':
  check(v[:,1].max()<=.015,name+' floor relief <=15mm')
  check((n[v[:,1]>.0121,1]>.999).all(),name+' every flat glyph faces upwards')
 if name=='lookout_semicircle_2m':
  check(np.allclose(v.min(0)[[0,2]],[-1,-1],atol=1e-6) and np.allclose(v.max(0)[[0,2]],[1,0],atol=1e-6),'Semicircle actual2m chord/1m projection')
  check(abs(row['deck_top_y_m']-.12)<1e-6 and row['connectors']=={'left':[-1,.12,0],'right':[1,.12,0]},'Semicircle mounting contract')
for path in KIT.glob('*.glb.import'):
 uid=re.search(r'uid="(uid://[a-y0-8]+)"',path.read_text());uids.append(uid.group(1))
check(len(set(uids))==len(uids)==21,'All21 GLB UIDs unique')
preserved={p:h for p,h in ref['existing_kit_sha256'].items() if Path(p).name not in ['README.md','kit_manifest.json']}
check(all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in preserved.items()),'Every original street-kit asset/material/import/palette preserved',{'files':len(preserved)})
check(len(m['assets'])==21 and m['unique_triangles']==sum(x['triangles'] for x in m['assets'].values()),'Combined21-piece catalogue totals')
check(not list(KIT.glob('*.tscn')) and not list(KIT.glob('*layout*')),'No game scene/layout delivered')
alcatraz=subprocess.check_output(['git','diff','--name-only','origin/wp-3d-scene...HEAD','--','assets/landmarks/alcatraz_island'],cwd=ROOT,text=True)
check(not alcatraz.strip(),'Branch introduces no Alcatraz asset changes')
ground_dir='assets/landmarks/_shared/ground_detail';ground_files=[p for p in subprocess.check_output(['git','ls-tree','-r','--name-only',ref['ground_review_commit'],ground_dir],cwd=ROOT,text=True).splitlines() if str(Path(p).parent)==ground_dir]
check(all((OUT/'project'/path).read_bytes()==subprocess.check_output(['git','show',ref['ground_review_commit']+':'+path],cwd=ROOT) for path in ground_files),'Pinned ground fixture unchanged',{'commit':ref['ground_review_commit'],'files':len(ground_files)})
report={'author':'黄忠','virtual_user_id':m['virtual_user_id'],'checks':checks,'passed':all(c['passed'] for c in checks),'new_assets':rows,'new_triangles':sum(x['triangles'] for x in rows.values()),'new_surfaces':len(rows),'combined_triangles':m['unique_triangles'],'combined_surfaces':len(m['assets'])}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('LOOKOUT_GEOMETRY',report['passed'],len(checks),report['new_triangles'],report['combined_triangles'])
if not report['passed']:sys.exit(1)
