from pathlib import Path
import json,sys,hashlib,re,numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[4];SRC=Path(__file__).resolve().parent;KIT=ROOT/'assets/rooms/_shared/church_kit';OUT=ROOT/'output/church-kit-423';sys.path.insert(0,str(ROOT/'tools/art'))
from verify_chef_sign import load_glb,accessor
original=json.loads((SRC/'original-files.json').read_text());m=json.loads((KIT/'kit_manifest.json').read_text());checks=[];uids=[];rows={}
def check(ok,label,evidence=None):checks.append({'check':label,'passed':bool(ok),'evidence':evidence})
files={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'assets/rooms/poi_church').rglob('*') if p.is_file()}
check(files==original['sha256'],'Entire live poi_church directory byte-identical (including no added/deleted files)',{'files':len(files),'baseline':original['base']})
for name,row in m['assets'].items():
 path=KIT/row['file'];d,b=load_glb(path);p=d['meshes'][0]['primitives'][0];v=np.array(accessor(d,b,p['attributes']['POSITION']));n=np.array(accessor(d,b,p['attributes']['NORMAL']));ix=np.array(accessor(d,b,p['indices'])).reshape(-1,3);t=v[ix]
 check(hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256'],name+' manifest digest')
 check(len(d['meshes'])==1 and len(d['meshes'][0]['primitives'])==1,name+' one mesh/surface')
 check(d['meshes'][0]['name']==name+'_mobile',name+' mesh name')
 check(len(ix)==row['triangles'],name+' triangles match',len(ix))
 check(np.allclose([v.min(0),v.max(0)],row['bounds'],atol=1e-6),name+' measured bounds')
 check(not d.get('skins') and not d.get('animations') and not d.get('cameras') and not d.get('extensions',{}).get('KHR_lights_punctual'),name+' no rigs/animations/cameras/lights')
 check(np.isfinite(v).all() and np.isfinite(n).all(),name+' finite mesh')
 check((np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1)>1e-10).all(),name+' nondegenerate triangles')
 if row['material']=='atlas':
  check(path.read_bytes()==(ROOT/row['reuse_from']).read_bytes(),name+' original GLB bytes copied')
  check(d.get('images')==[{'uri':'room_albedo_ao.png'}],name+' atlas URI resolves inside new kit')
 else:check(not d.get('images'),name+' no embedded/source atlas')
 if row['material']=='glass':
  uv=np.array(accessor(d,b,p['attributes']['TEXCOORD_0']));slot=np.rint(uv[:,0]*8-.5).astype(int)
  check((abs(uv[:,0]-(slot+.5)/8)<1e-7).all() and (slot>=0).all() and (slot<6).all() and np.allclose(uv[:,1],.5),name+' only six valid colour-group centres')
  check('TEXCOORD_1' not in p['attributes'],name+' no stale original UV channel')
  check(len(set(slot))>=5,name+' multiple independently recolourable groups',sorted(set(int(i) for i in slot)))
 cfg=(KIT/(row['file']+'.import')).read_text();uid=re.search(r'uid="(uid://[a-y0-8]+)"',cfg)
 check(uid is not None,name+' Godot UID');uids.append(uid.group(1) if uid else '')
 for line in ['nodes/root_script=null','gltf/texture_map_mode=1','meshes/light_baking=1']:check(line in cfg,name+' '+line)
 if row['material']=='atlas':
  source_uid=re.search(r'uid="(uid://[a-y0-8]+)"',(ROOT/(row['reuse_from']+'.import')).read_text()).group(1)
  check(uid.group(1)!=source_uid,name+' independent new UID, no live-resource alias')
 rows[name]={'triangles':len(ix),'bounds':[v.min(0).tolist(),v.max(0).tolist()]}
check(len(uids)==len(set(uids)),'Every module has unique Godot UID')
check((KIT/'room_albedo_ao.png').read_bytes()==(ROOT/'assets/rooms/poi_church/room_albedo_ao.png').read_bytes(),'Shared copied atlas byte-identical')
check(Image.open(KIT/'room_albedo_ao.png').size==(2048,2048),'One2048 atlas plus tiny glass palettes')
for palette in ['classic','meadow']:
 p=KIT/('glass_palette_'+palette+'.png');check(Image.open(p).size==(8,1),palette+' 8-cell colour resource')
 cfg=Path(str(p)+'.import').read_text();check('compress/mode=0' in cfg and 'mipmaps/generate=false' in cfg,palette+' uncompressed/no mip colour cells')
for name in ['wall_straight_2m','wall_pointed_2m','wall_rose_2m','roof_band_2m','beam_2m']:
 b=rows[name]['bounds'];check(abs(b[0][0]+1)<1e-6 and abs(b[1][0]-1)<1e-6,name+' exact2m module length')
corner=rows['wall_corner_2m']['bounds'];check(abs(corner[1][0]-1)<1e-6 and abs(corner[1][2]-1)<1e-6,'Corner arms each1m')
check(m['assets']['rose_frame']['dimensions_m'][0]<2 and m['assets']['rose_frame']['dimensions_m'][1]<2,'Rose assembly fits2m bay')
check(abs(rows['steps_2m']['bounds'][1][1]-.54)<1e-6,'Three18cm stair risers total54cm')
check(not list(KIT.rglob('*layout*')) and not list(KIT.rglob('*.tscn')),'Kit contains no new POI layout or assembled runtime scene')
check(3.9-m['assets']['wood_pew']['dimensions_m'][0]>=.8,'Example central aisle from actual pew bounds >=.8m',3.9-m['assets']['wood_pew']['dimensions_m'][0])
check((SRC/'.gdignore').exists(),'Review/source folder excluded from game import')
check((KIT/'church_kit_import.gd.uid').exists() and (KIT/'stained_glass.gdshader.uid').exists(),'Import script and shader Godot UIDs')
report={'author':'黄忠','virtual_user_id':m['virtual_user_id'],'checks':checks,'passed':all(c['passed'] for c in checks),'original_files':len(files),'assets':rows,'unique_triangles':sum(x['triangles'] for x in rows.values()),'unique_surfaces':len(rows)}
(OUT/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
for c in checks:
 if not c['passed']:print('FAIL',c)
print('KIT_GEOMETRY',report['passed'],len(checks),report['unique_triangles'],len(files))
if not report['passed']:sys.exit(1)
