#!/usr/bin/env python3
"""Independent exported GLB / triangle-BVH checks; Blender background."""
import hashlib,json,sys,subprocess,math
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_warming_cabinet import geometry,matrix,bounds
from verify_chef_sign import load_glb,accessor
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/kitchen-213';KIT=ROOT/'assets/rooms/basic_room';SRC=ROOT/'tools/art/source/kitchen_213'
BASE='154ce6421448e26e42ee225ba7018638ae756394'

def main():
 report={'checks':[],'assets':{},'pairs':[],'method':'Actual GLB vertices and transforms, AABB broad phase and triangle BVH intersections; ray tests prove stove support and true firebox cavities. Positive controls cover collision detector.'}
 def check(ok,label):
  report['checks'].append({'check':label,'passed':bool(ok)})
  if not ok:print('FAIL',label,flush=True)
 c=json.loads((SRC/'contract.json').read_text());layout=json.loads((KIT/'layout.json').read_text());original=json.loads(subprocess.check_output(['git','show',BASE+':assets/rooms/basic_room/layout.json'],cwd=ROOT))
 by={r['name']:r for r in layout['assets']};old={r['name']:r for r in original['assets']}
 for name in ['room_shell','window_wall','back_wall','arched_window','window_garden','window_plant','bench','green_door']:
  check(by[name]==old[name],name+' layout unchanged')
  p=KIT/by[name]['file'];check(p.read_bytes()==subprocess.check_output(['git','show',BASE+':'+str(p.relative_to(ROOT))],cwd=ROOT),name+' GLB byte-identical')
 check('hearth' not in by and 'kettle' not in by,'old hearth and kettle unplaced')
 check(by['spice_rack']['position']==[-2.83,1.72,-1.575] and by['spice_rack']['yaw_degrees']==90,'spice rack keeps approved location')
 checks=[]
 for name in c['assets']:
  p=KIT/(name+'.glb');d,b,v,t,g=geometry(p);lo,hi=np.array(bounds(v));ntris=len(t)
  check(ntris==c['assets'][name]['triangles'],name+' GLB triangle count matches stats')
  check('gltf/texture_map_mode=1' in p.with_suffix('.glb.import').read_text(),name+' texture map mode 1')
  check(all(n.get('scale',[1,1,1])==[1,1,1] for n in d['nodes']),name+' unscaled nodes')
  bad=deg=0
  uv_allowed=[s['gltf_uv'] for s in c['atlas']['swatches'].values()]
  for mesh in d['meshes']:
   for pr in mesh['primitives']:
    xyz=np.array(accessor(d,b,pr['attributes']['POSITION']));norm=np.array(accessor(d,b,pr['attributes']['NORMAL']));ix=np.array(accessor(d,b,pr['indices'])).reshape(-1,3);uv=np.array(accessor(d,b,pr['attributes']['TEXCOORD_0']));cross=np.cross(xyz[ix[:,1]]-xyz[ix[:,0]],xyz[ix[:,2]]-xyz[ix[:,0]])
    deg+=int((np.linalg.norm(cross,axis=1)<1e-10).sum());bad+=int((np.sum(cross*norm[ix].sum(1),axis=1)<-1e-9).sum())
    check(all(min(np.linalg.norm(q-a) for a in uv_allowed)<1e-6 for q in uv),name+' approved constant atlas UVs')
  check(deg==0,name+' no degenerate triangles');check(bad==0,name+' normal and winding agreement')
  report['assets'][name]={'bounds':[lo.tolist(),hi.tolist()],'size_xyz':(hi-lo).tolist(),'triangles':ntris,'surfaces':sum(len(m['primitives']) for m in d['meshes']),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'groups':{n:bounds(q) for n,q in g.items()}}
  if name=='kitchen_range_3':
   check(abs((hi-lo)[0]-1.35)<1e-6,'range actual width 1.35 m')
   for key,at in c['sockets_local'].items():
    n=next(n for n in d['nodes'] if n.get('name')==key);check('mesh' not in n and np.max(abs(np.array(n.get('translation',[0,0,0]))-at))<1e-6,'empty local socket '+key)
   check(set(['lid_2','lid_3']).issubset(g),'two independent cap meshes')
 # Full placed scene geometry for all new objects, plus all preserved obstacles.
 rows={}
 for row in layout['assets']+layout.get('instances',[]):
  asset=by[row.get('asset',row['name'])];_,_,v,t,g=geometry(KIT/asset['file'],matrix(row['position'],row.get('yaw_degrees',0)));rows[row['name']]={'v':v,'t':t,'g':g,'bounds':np.array(bounds(v)),'tree':BVHTree.FromPolygons(v,t,all_triangles=True)}
 _,_,v,t,g=geometry(ROOT/'assets/props/warming_cabinet/warming_cabinet_b.glb',matrix([-2.85,.082,-1.69],90));rows['warming_cabinet']={'v':v,'t':t,'g':g,'bounds':np.array(bounds(v)),'tree':BVHTree.FromPolygons(v,t,all_triangles=True)}
 targets=['kitchen_range_3','spice_rack','cookbook_wall'];seen=set()
 for a in targets:
  av=rows[a];alo,ahi=av['bounds']
  for b,bv in rows.items():
   if a==b or tuple(sorted([a,b])) in seen:continue
   seen.add(tuple(sorted([a,b])));blo,bhi=bv['bounds'];sep=np.maximum(alo-bhi,blo-ahi);pairs=[];support=[];flame_logs=[]
   if (sep<=0).all():
    for ia,ib in av['tree'].overlap(bv['tree']):
     floor_contact=b=='room_shell' and max(bv['v'][i].y for i in bv['t'][ib])<=.0826 and min(av['v'][i].y for i in av['t'][ia])>=.081999
     # Named logs are two Z-axis cylinders radius .045, centred at
     # local x=-.45 +/- .09, y=.18, z=.08. Only their surfaces
     # may be inside the intended flame volume; masonry is never exempt.
     ps=[av['v'][j] for j in av['t'][ia]]
     log_contact=a=='kitchen_range_3' and b=='fire' and any(all((p.x-xx)**2+(p.y-.262)**2<=.045001**2 and -2.575001<=p.z<=-2.324999 for p in ps) for xx in [-2.59,-2.41])
     (support if floor_contact else flame_logs if log_contact else pairs).append([ia,ib])
   check(not pairs,a+' clear of '+b);report['pairs'].append({'a':a,'b':b,'axis_separation_m':sep.tolist(),'intersections':len(pairs),'floor_contact_pairs':len(support),'intentional_fire_log_pairs':len(flame_logs)})
 # Check the rest of the explicitly requested obstacle set pairwise, too.
 required=['kitchen_range_3','warming_cabinet','spice_rack','cookbook_wall','sink_cabinet','arched_window','bench','green_door']
 for i,a in enumerate(required):
  for b in required[i+1:]:
   if tuple(sorted([a,b])) in seen:continue
   seen.add(tuple(sorted([a,b])));aa=rows[a];bb=rows[b];sep=np.maximum(aa['bounds'][0]-bb['bounds'][1],bb['bounds'][0]-aa['bounds'][1]);hits=aa['tree'].overlap(bb['tree']) if (sep<=0).all() else []
   check(not hits,a+' clear of '+b);report['pairs'].append({'a':a,'b':b,'axis_separation_m':sep.tolist(),'intersections':len(hits)})
 # Stove 1 flame is a volume effect: logs can lie within flame by design. Audit
 # outside masonry separately from this intentional internal flame/log overlap.
 stove=rows['kitchen_range_3']
 body_points={tuple(p) for p in stove['g']['body']}
 body_tris=[t for t in stove['t'] if all(tuple(stove['v'][i]) in body_points for i in t)]
 tree=BVHTree.FromPolygons(stove['v'],body_tris,all_triangles=True)
 for key,at in c['sockets_world'].items():
  if not key.startswith('stove_'):continue
  # Pots' flat bottoms span the opening; four radial support points on iron ring.
  ys=[]
  for dx,dz in [(0.055,0),(-.055,0),(0,.055),(0,-.055)]:
   hit=tree.ray_cast(Vector((at[0]+dx,at[1]+.01,at[2]+dz)),Vector((0,-1,0)),.04);ys.append(hit[0].y if hit[0] is not None else None)
  check(all(y is not None and abs(y-.98)<1e-6 for y in ys),key+' real support plane at world Y .980')
  checks.append({'socket':key,'radial_support_y':ys})
 report['support_rays']=checks
 check(all(abs(c['sockets_world'][f'stove_{i+1}_top'][0]-c['sockets_world'][f'stove_{i}_top'][0])>=.33 for i in [1,2]),'burner spacing >=0.33 m')
 for i in [1,2,3]:
  at=c['sockets_world'][f'stove_{i}_top'];hit=tree.ray_cast(Vector((at[0],.55,-2.1)),Vector((0,0,-1)),1)
  check(hit[0] is not None and hit[0].z< -2.6,'firebox '+str(i)+' front is genuinely open / ray reaches interior back')
 # Deliberately translate the stove through the wall to prove detector sensitivity.
 wall=rows['back_wall'];shifted=[p+Vector((0,0,-.30)) for p in stove['v']];hits=BVHTree.FromPolygons(shifted,stove['t'],all_triangles=True).overlap(wall['tree']);check(bool(hits),'positive control catches stove/wall penetration');report['positive_control_pairs']=len(hits)
 # Pinned #434 pot models, all three sockets with big pots; exact bottom contact.
 path=OUT/'project/assets/props/stove_pot/stove_pot.glb';doc,data=load_glb(path)
 # Prune the normal branch from a temporary JSON-equivalent GLB by using BVH
 # group selection: all big nodes have distinct vertices and are indexed below.
 bigroot=next(n for n in doc['nodes'] if n.get('name')=='pot_big');keep=set()
 def walk(idx):
  keep.add(idx)
  for child in doc['nodes'][idx].get('children',[]):walk(child)
 for child in bigroot['children']:walk(child)
 big_names={doc['nodes'][i]['name'] for i in keep if 'mesh' in doc['nodes'][i]}
 # Read via original scene after zeroing normal primitive indices in a local file.
 from copy import deepcopy
 d=deepcopy(doc)
 normal=next(n for n in d['nodes'] if n.get('name')=='pot_normal');normal['children']=[]
 import struct
 j=json.dumps(d,separators=(',',':')).encode();j+=b' '*((-len(j))%4);blob=bytes(data);blob+=b'\0'*((-len(blob))%4);temp=OUT/'big-only.glb';temp.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(j)+len(blob))+struct.pack('<I4s',len(j),b'JSON')+j+struct.pack('<I4s',len(blob),b'BIN\0')+blob)
 pots=[]
 for i in [1,2,3]:
  at=c['sockets_world'][f'stove_{i}_top'];_,_,v,t,g=geometry(temp,matrix(at));lo,hi=np.array(bounds(v));check(abs(lo[1]-.98)<1e-6,'Big Pot '+str(i)+' bottom touches .980 support')
  pot_tree=BVHTree.FromPolygons(v,t,all_triangles=True)
  raw_hits=pot_tree.overlap(tree);penetration=[];contacts=[]
  for a,b in raw_hits:
   is_support=max(stove['v'][q].y for q in body_tris[b])<=.980001 and min(v[q].y for q in t[a])>=.979999
   (contacts if is_support else penetration).append([a,b])
  check(not penetration,'Big Pot '+str(i)+' does not penetrate stove or flue')
  report.setdefault('pot_support_intersections',[]).append({'stove':i,'contact_pairs':len(contacts),'penetration_pairs':len(penetration)})
  pots.append((v,t,pot_tree,[lo.tolist(),hi.tolist()]))
 for i in range(2):check(not pots[i][2].overlap(pots[i+1][2]),'adjacent Big Pots '+str(i+1)+'/'+str(i+2)+' do not intersect')
 report['big_pot_world_bounds']=[p[3] for p in pots]
 # World bounds of actual exported assets and sockets for program handoff.
 report['sockets_world']=c['sockets_world'];report['world_bounds']={n:r['bounds'].tolist() for n,r in rows.items()}
 report['failures']=[r for r in report['checks'] if not r['passed']];(OUT/'glb-validation.json').write_text(json.dumps(report,indent=2)+'\n');print('KITCHEN_213_BINARY_QA',len(report['checks']),'checks',len(report['failures']),'failures',flush=True)
 if report['failures']:raise RuntimeError('Kitchen validation failed')
if __name__=='__main__':main()
