"""Validate actual exported GLB geometry, cross-module contacts and provenance."""
from pathlib import Path
import sys,json,math,hashlib,subprocess
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from verify_warming_cabinet import geometry,matrix,bounds
from verify_chef_sign import load_glb,accessor
ROOT=Path(__file__).resolve().parents[2];KIT=ROOT/'assets/rooms/mine_hut';OUT=ROOT/'output/minehut-308'
def main():
 layout=json.loads((KIT/'layout.json').read_text());stats=json.loads((KIT/'asset_stats.json').read_text());report={'checks':[],'pairs':[],'assets':{},'method':'Actual GLB vertices; triangle BVH cross-module intersections, support-height filter; capsule blocking separately checked in Godot.'}
 def check(ok,label):
  report['checks'].append({'check':label,'passed':bool(ok)})
  if not ok:print('FAIL',label,flush=True)
 rows={}
 image=bpy.data.images.load(str(KIT/'room_albedo_ao.png'));pixels=np.array(image.pixels[:],dtype=np.float32).reshape((2048,2048,4))
 for row in layout['assets']:
  name=row['name'];file=KIT/row['file'];d,blob,v,t,g=geometry(file,matrix(row['position'],row['yaw_degrees']));bb=np.array(bounds(v));tree=BVHTree.FromPolygons(v,t,all_triangles=True)
  rows[name]={'v':v,'t':t,'bb':bb,'tree':tree}
  check(len(t)==next(a['triangles'] for a in stats['assets'] if a['name']==name),name+' actual GLB triangle count')
  check('gltf/texture_map_mode=1' in Path(str(file)+'.import').read_text(),name+' texture_map_mode=1')
  check(d.get('images')==[{'uri':'room_albedo_ao.png'}],name+' one shared external atlas')
  dark_samples=0;sample_count=0
  for m in d['meshes']:
   for pr in m['primitives']:
    uv=np.array(accessor(d,blob,pr['attributes']['TEXCOORD_0']));ix=np.array(accessor(d,blob,pr['indices'])).reshape((-1,3))
    probes=np.concatenate([uv,uv[ix].mean(axis=1)])
    xy=np.clip(np.floor(probes*np.array([2048,-2048])+np.array([0,2048])).astype(int),0,2047)
    colors=pixels[xy[:,1],xy[:,0],:3];dark_samples+=int((np.max(colors,axis=1)<.00001).sum());sample_count+=len(probes)
  check(dark_samples==0,name+' UV vertices and triangle centres never sample empty black atlas')
  report['assets'][name]={'world_bounds':bb.tolist(),'triangles':len(t),'sha256':hashlib.sha256(file.read_bytes()).hexdigest()}
 # Revision contract: footprint unchanged, thick larger hide and real recess.
 shell=rows['room_shell']['bb'];hide=rows['white_hide_rug']['bb'];mine=rows['mine_entrance']['bb']
 check(np.allclose((shell[1]-shell[0])[[0,2]],[6.8,6.4],atol=1e-5),'original 6.8 x 6.4 m floor retained')
 check(abs((hide[1]-hide[0])[0]-2.6)<.02 and abs((hide[1]-hide[0])[2]-2.0)<.06,'thick hide approx 2.6 x 2.0 m including edge tufts')
 check((hide[1]-hide[0])[1]>=.08,'hide has at least 8 cm actual padded thickness')
 depth=-3.09-mine[0][2];check(2.49<=depth<=2.55,'actual mine recess extends 2.50 m behind wall plus end cap')
 report['revision_dimensions']={'hide_size_xyz':(hide[1]-hide[0]).tolist(),'tunnel_depth_including_end_cap':float(depth),'floor_xz':(shell[1]-shell[0])[[0,2]].tolist()}
 # Cast outwards from the actual recess, including the former last-section gap.
 # Every radial ray must encounter stone: a closed far card alone is insufficient.
 misses=[];probe_count=0
 for z in np.linspace(-2.66,-2.83,18):
  t=(-z-.37)/2.5
  origin=Vector((-.30,.082+(1-.6*t)-t,-2.72+z))
  for a in np.linspace(0,math.tau,32,endpoint=False):
   probe_count+=1
   hit=rows['mine_entrance']['tree'].ray_cast(origin,Vector((math.cos(a),math.sin(a),0)),3)
   if hit[0] is None:misses.append([float(z),float(a)])
 check(not misses,'far tunnel lining is closed: radial mesh rays cannot escape to the background')
 report['tunnel_closure']={'radial_probes':probe_count,'missing_hits':misses,'local_z_interval':[-2.83,-2.66]}
 # Rebakings may change UV packing. Unrequested prop geometry must stay v1-exact.
 changed={'left_wall','back_wall','mine_entrance','hearth_stones','white_hide_rug','stove_stone_base','tunnel_lamp_glow'}
 report['retained_geometry']=[]
 for row in layout['assets']:
  name=row['name']
  if name in changed:continue
  baseline=OUT/'baseline.glb';baseline.write_bytes(subprocess.check_output(['git','show','4f345477:assets/rooms/mine_hut/'+row['file']],cwd=ROOT))
  old=np.array(geometry(baseline)[2]);new=np.array(geometry(KIT/row['file'])[2])
  errors=[]
  for a,b in [(old,new),(new,old)]:
   tree=KDTree(len(b))
   for i,point in enumerate(b):tree.insert(Vector(point),i)
   tree.balance();errors.append(max(tree.find(Vector(point))[2] for point in a))
  check(max(errors)<1e-5,name+' local geometry retained from v1 within 0.01 mm')
  report['retained_geometry'].append({'asset':name,'max_bidirectional_vertex_distance_m':max(errors)})
 # Structural joinery and designed assembly contacts, narrowly enumerated.
 legal={tuple(sorted(pair)):reason for pair,reason in [
  (('left_wall','back_wall'),'two-wall timber corner joint'),
  (('room_shell','left_wall'),'structural post foot seated into foundation'),
  (('room_shell','back_wall'),'structural post foot seated into foundation'),
  (('room_shell','mine_entrance'),'rock surround base seated 0.030 m into foundation'),
  (('hearth_stones','square_stool'),'stool stands on hearth slab'),
  (('mine_entrance','tunnel_lamp_glow'),'tunnel lantern glass contained in its cap and guard'),
  (('mine_entrance','back_wall'),'rock surround and timber bedded into true wall aperture'),
  (('sorting_bench','sorting_tray'),'tray rests on workbench'),
  (('sorting_bench','quartz_and_tools'),'minerals/tools rest on workbench'),
  (('sorting_tray','quartz_and_tools'),'tools beside tray lip'),
  (('grilling_stove','stove_embers'),'coals inside stove firebox'),
  (('hearth_stones','grilling_stove'),'stove feet rest on hearth slab'),
  (('left_wall','grilling_stove'),'flue rear mounting collar contacts wall'),
  (('left_shelf','shelf_lantern'),'lantern rests on shelf'),
  (('low_cabinet','cabinet_lantern'),'lantern rests on cabinet top'),
 ]}
 for n in ['mine_lantern_-1','mine_lantern_1','shelf_lantern','cabinet_lantern']:
  glow=n.replace('mine_lantern_','mine_lantern_glow_') if n.startswith('mine_') else n.replace('lantern','lantern_glow')
  legal[tuple(sorted([n,glow]))]='glass contained in original lantern frame'
 for s in ['-1','1']:
  legal[tuple(sorted(['mine_lantern_'+s,'mine_lantern_hanger_'+s]))]='closed suspension ring joins lantern handle'
  legal[tuple(sorted(['mine_entrance','mine_lantern_hanger_'+s]))]='iron hanging bracket mounted to rock surround'
 names=list(rows)
 for i,a in enumerate(names):
  aa=rows[a]
  for b in names[i+1:]:
   bb=rows[b];sep=np.maximum(aa['bb'][0]-bb['bb'][1],bb['bb'][0]-aa['bb'][1]);hits=aa['tree'].overlap(bb['tree']) if max(sep)<=1e-6 else []
   support=[];bad=[]
   for ia,ib in hits:
    ps=[aa['v'][k] for k in aa['t'][ia]]+[bb['v'][k] for k in bb['t'][ib]]
    # Floor top contact only; no general exemption for wall or furniture intersections.
    others=([bb['v'][k] for k in bb['t'][ib]] if a=='room_shell' else [aa['v'][k] for k in aa['t'][ia]])
    floor=('room_shell' in [a,b] and min(v.y for v in others)>=.08199 and max(v.y for v in ps if v.y<.083)<.083) if any(v.y<.083 for v in ps) else False
    (support if floor else bad).append((ia,ib))
   reason=legal.get(tuple(sorted([a,b])))
   if set([a,b]) in [set(['hearth_stones','stove_stone_base']),set(['stove_stone_base','grilling_stove'])]:
    overlap_y=min(aa['bb'][1][1],bb['bb'][1][1])-max(aa['bb'][0][1],bb['bb'][0][1])
    if abs(overlap_y)<1e-5:reason='masonry base support plane contact only, within 0.01 mm'

   if a=='back_wall' and b=='ivo_wall_helmet' and bad:
    peg_only=all(all(2.63<=bb['v'][k].x<=2.67 and 2.58<=bb['v'][k].y<=2.70 and -3.04<=bb['v'][k].z<=-2.78 for k in bb['t'][ib]) for ia,ib in bad)
    if peg_only:reason='only the named small helmet hanging peg enters wall; original helmet mesh is clear'

   # Threshold stones intentionally bed into floor foundation.
   if set([a,b])==set(['room_shell','exit_steps']):reason='exit stone threshold bedded into front foundation'
   if bad or support:report['pairs'].append({'a':a,'b':b,'intersections':len(bad),'floor_contact_pairs':len(support),'reason':reason,'axis_separation':sep.tolist()})
   check(not bad or reason is not None,a+' / '+b+' no unintended triangle intersection')
 # Exact Ivo silhouette is retained, translation to its own mounting pivot only.
 _,_,original,ot,_=geometry(OUT/'ivo_runtime.glb');old=np.array(original);center=(old.min(0)+old.max(0))/2
 local=geometry(KIT/'ivo_wall_helmet.glb')[2];actual=np.array(local)
 # All original positions must occur in final output; the added rear hanging peg is excluded.
 distances=np.sqrt(((old[:,None,:]-center-actual[None,:,:])**2).sum(2)).min(1)
 missing=int((distances>2e-6).sum())
 check(missing==0,'Ivo original helmet vertex positions retained within 2 micrometres under pure translation')
 report['helmet_reuse']={'original_triangles':len(ot),'original_vertices':len(old),'missing_original_positions':missing,'max_vertex_distance_m':float(distances.max()),'added_geometry':'rear mounting peg only'}
 # Actual mesh support rays, including the two lanterns and stool feet plane.
 report['support_gaps']=[]
 for asset,support in [('cabinet_lantern','low_cabinet'),('shelf_lantern','left_shelf'),('square_stool','hearth_stones'),('round_stool','room_shell'),('sorting_tray','sorting_bench'),('stove_stone_base','hearth_stones'),('grilling_stove','stove_stone_base')]:
  row=next(x for x in layout['assets'] if x['name']==asset);bottom=float(rows[asset]['bb'][0][1]);start=Vector((row['position'][0],bottom+.001,row['position'][2]));hit=rows[support]['tree'].ray_cast(start,Vector((0,-1,0)),.04)
  gap=bottom-hit[0].y if hit[0] is not None else None
  check(gap is not None and -.00001<=gap<=.001,asset+' rests on '+support+' within 1 mm, no penetration')
  report['support_gaps'].append({'asset':asset,'support':support,'gap_m':gap})
 # A deliberate penetration must produce hits (positive control).
 a=rows['square_stool'];b=rows['grilling_stove'];shift=Vector((-1.02,.4,-.28));tree=BVHTree.FromPolygons([v+shift for v in a['v']],a['t'],all_triangles=True)
 check(bool(tree.overlap(b['tree'])),'positive control detects stool through stove')
 check(stats['scene_triangles']<=200000 and stats['static_draw_surfaces']<=60,'scene budget')
 report['failures']=[c for c in report['checks'] if not c['passed']]
 (OUT/'geometry-validation.json').write_text(json.dumps(report,indent=2)+'\n');print('GEOMETRY_QA',len(report['checks']),len(report['failures']),flush=True)
 if report['failures']:raise RuntimeError('Mine Hut geometry validation failed')
if __name__=='__main__':main()
