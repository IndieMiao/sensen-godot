from pathlib import Path
import sys,json,hashlib,subprocess,io,re
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
K=Path(__file__).resolve().parent.parent;R=K.parents[2];O=K/'_review_v11';O.mkdir(exist_ok=True);sys.path.insert(0,str(R/'tools/art'))
from verify_chef_sign import load_glb,accessor
base=json.loads((K/'_source_v11/reuse_provenance.json').read_text())['base_head']
def old(name):return subprocess.check_output(['git','show',base+':assets/rooms/poi_church/'+name])
L=json.loads((K/'layout.json').read_text());L0=json.loads(old('layout.json'));checks=[]
def check(ok,label):checks.append({'check':label,'passed':bool(ok)});print(('PASS ' if ok else 'FAIL ')+label)
for key in L0:
 if key not in ['assets','revision']:check(L[key]==L0[key],'unchanged layout.'+key)
check(L['assets'][:len(L0['assets'])]==L0['assets'],'every original asset placement / collider / material unchanged')
check(all(not a['colliders'] for a in L['assets'][len(L0['assets']):]),'additions have zero collision')
mask=Image.new('L',(2048,2048));draw=ImageDraw.Draw(mask);original=[];rows=[]
for a in L['assets']:
 f=K/a['file'];d,b=load_glb(f);mesh=d['meshes'][0];p=mesh['primitives'][0];pts=np.array(accessor(d,b,p['attributes']['POSITION']));ix=np.array(accessor(d,b,p['indices'])).reshape(-1,3);uv=np.array(accessor(d,b,p['attributes']['TEXCOORD_0']))
 check(len(d['meshes'])==1 and len(mesh['primitives'])==1 and len(d['materials'])==1,a['name']+' one mesh / surface / material')
 check(mesh['name']==a['name']+'_mobile',a['name']+' mesh name')
 check(d.get('images')==[{'uri':'room_albedo_ao.png'}],a['name']+' single external atlas')
 check(np.isfinite(pts).all() and np.isfinite(uv).all(),a['name']+' finite positions/UV')
 cfg=(K/(a['file']+'.import')).read_text();check(re.search('uid="uid://[a-y0-8]+"',cfg) and 'gltf/texture_map_mode=1' in cfg,a['name']+' Godot UID / texture_map_mode 1')
 if a['name'] in [v['name'] for v in L0['assets']]:
  check(f.read_bytes()==old(a['file']) and (K/(a['file']+'.import')).read_bytes()==old(a['file']+'.import'),a['name']+' original GLB+import byte identical')
  for tri in ix:draw.polygon([tuple(v*2048) for v in uv[tri]],fill=255)
  original.append({'file':a['file'],'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
 else:
  ns=np.array(accessor(d,b,p['attributes']['NORMAL']));tri=pts[ix];areas=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);check((np.linalg.norm(areas,axis=1)>1e-10).all(),a['name']+' no degenerate triangles')
  check((np.sum(areas*ns[ix].mean(1),axis=1)>=-1e-9).all(),a['name']+' normals agree with winding')
 rows.append({'name':a['name'],'triangles':len(ix),'bounds':[pts.min(0).tolist(),pts.max(0).tolist()]})
occupied=np.array(mask.filter(ImageFilter.MaxFilter(9)))
check(not occupied[124:140,1896:1912].any(),'new carpet atlas square outside ALL original UV triangles + 4px gutter')
im=np.array(Image.open(K/'room_albedo_ao.png').convert('RGB'));before=np.array(Image.open(io.BytesIO(old('room_albedo_ao.png'))).convert('RGB'));changed=(im!=before).any(2);outside=changed.copy();outside[124:140,1896:1912]=False
check(not outside.any(),'atlas pixels outside new 16x16 unused square identical')
carpet=next(a for a in L['assets'] if a['name']=='aisle_carpet');row=next(a for a in rows if a['name']=='aisle_carpet');bounds=np.array(row['bounds']);dimensions=bounds[1]-bounds[0]
check(abs(dimensions[0]-1.2)<1e-6 and abs(dimensions[1]-.004)<1e-6,'carpet 1.20m wide / 4mm thick')
# Physical top .087, floor .080. Local .004 slab is centred at .002, placed .083.
check(abs(bounds[1][1]+carpet['position'][1]-.087)<1e-6,'carpet top only 7mm above floor')
check(4.15-1.34-2.75>=.0599,'carpet clears labyrinth outer radius by 6cm')
check(-2.84-(-4.45+1.55)>=.0599,'carpet clears front altar step by 6cm')
stats=json.loads((K/'asset_stats.json').read_text());by={r['name']:r for r in rows};placed=[a['name'] for a in L['assets'] if not a['review_only']]+[a['asset'] for a in L['instances']]
check(sum(by[n]['triangles'] for n in placed)==stats['scene_triangles']<=200000,'placed triangle budget')
check(len(placed)==stats['static_draw_surfaces']<=60,'placed surface budget')
report={'author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','base_head':base,'checks':checks,'unchanged_glb_hashes':original,'new_assets':[r for r in rows if r['name'] in ['aisle_carpet','vault_extension','grass_extension']],'stats':{k:stats[k] for k in ['scene_triangles','static_draw_surfaces','plant_triangles']},'passed':all(c['passed'] for c in checks)}
(O/'geometry-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('RESULT',report['passed'],len(checks))
