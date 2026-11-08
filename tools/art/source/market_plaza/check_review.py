"""Validate exported live P0 navigation and actual transformed occluder meshes."""
from pathlib import Path
import json,math,sys
import numpy as np
ROOT=Path(__file__).resolve().parents[4]
folder=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'output/market-plaza-218/capture-v1'
nav=json.loads((folder/'navigation_snapshot.json').read_text())
report=json.loads((folder/'review.json').read_text())
meshes=json.loads((folder/'occluders.json').read_text())
layout=json.loads((ROOT/'assets/rooms/market_plaza/layout.json').read_text())
offset=np.array(nav['room_offset']);cell=nav['cell_m'];rows=nav['walkable'];h,w=len(rows),len(rows[0])
def walkable(x,z):
 i=math.floor((x+offset[0])/cell);j=math.floor(-(z+offset[2])/cell)
 return 0<=i<w and 0<=j<h and rows[j][i]=='1'
samples=np.array([[x,nav['floor_y'],z] for x in np.arange(-8,8.001,.5) for z in np.arange(-8,8.001,.5) if walkable(x,z)])
origins=np.repeat(samples,2,axis=0);origins[:,1]+=np.tile([1,1.6],len(samples))
pitch=math.radians(report['pitch']);yaw=math.radians(report['yaw'])
direction=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch)])
def hit(points,tri):
 v=tri[:,0];a=tri[:,1]-v;b=tri[:,2]-v
 c=np.cross(direction,b);det=np.einsum('ij,ij->i',a,c);mask=np.abs(det)>1e-9
 v,a,b,c,det=[x[mask] for x in [v,a,b,c,det]]
 answer=np.zeros(len(points),bool)
 for i in range(0,len(points),32):
  s=points[i:i+32,None,:]-v[None,:,:]
  u=np.einsum('ptj,tj->pt',s,c)/det;q=np.cross(s,a)
  z=np.einsum('ptj,j->pt',q,direction)/det;t=np.einsum('ptj,tj->pt',q,b)/det
  answer[i:i+32]=((u>=-1e-7)&(z>=-1e-7)&(u+z<=1+1e-7)&(t>1e-5)).any(axis=1)
 return answer
blocked={}
for m in meshes:
 tri=np.array(m['faces']).reshape(-1,3,3)
 if m['module'].startswith('stall_'):tri=tri[tri[:,:,1].min(axis=1)>1.8]
 if not len(tri):continue
 lo=tri.min(axis=(0,1));hi=tri.max(axis=(0,1));center=(lo+hi)/2;radius=np.linalg.norm(tri.reshape(-1,3)-center,axis=1).max()
 v=center-origins;along=v@direction;cross=np.einsum('ij,ij->i',v,v)-along**2
 ids=np.where((cross<=radius**2)&(along+radius>0))[0]
 ids=ids[hit(origins[ids],tri)]
 if len(ids):blocked[m['module']]={'count':len(ids),'points':origins[ids].tolist(),'sample_indices':ids.tolist()}
anchors={a['name']:a for a in layout['anchors']}
seat_names=[a['name'] for a in layout['anchors'] if a['name'].startswith('seat_')]
assert seat_names==['seat_1','seat_2']
assert anchors['use_counter']['module']=='stall_keeper'
assert anchors['stand_counter']['position']==anchors['stand_keeper']['position']
assert len([a for a in layout['assets'] if a['name'].startswith('corner_tree_') and 'pad' not in a['name']])==3
bar=report['views']['opening']['name_bars'].get('room:exit')
actor=report['views']['opening']['player_box']
gap=None
if bar:
 gap=math.hypot(max(actor[0]-bar[0]-bar[2],bar[0]-actor[0]-actor[2],0),max(actor[1]-bar[1]-bar[3],bar[1]-actor[1]-actor[3],0))
out={'nav_grid':[w,h],'walkable_cells':sum(r.count('1') for r in rows),'samples_05m':len(samples),'occlusion':blocked,
 'blocked_sample_count':len({i//2 for x in blocked.values() for i in x['sample_indices']}),
 'routes':report['anchor_routes'],'ring_path_failures':sum(p['points']==0 for p in report['ring_paths']),
 'seat_order':seat_names,'map_player_gap_px':gap,'pitch':report['pitch'],'yaw':report['yaw'],'width':report['camera_width'],
 'all_approaches_walkable':all(walkable(a['approach'][0],a['approach'][2]) for a in layout['anchors'] if a['name'].startswith('seat_')),
 'mesh_source':'Huangzhong #877 finished GLBs 288b47b94f966981603b3d132552d6b16f923303: actual transformed canopy triangles above 1.8m, plus complete tree meshes; live P0 collision navigation.'}
keeper=next(m for m in meshes if m['module']=='stall_keeper')
tri=np.array(keeper['faces']).reshape(-1,3,3)
tri=tri[tri[:,:,1].min(axis=1)>1.8]
keeper_points=np.array([[1.75,1.05,1.75],[1.75,1.65,1.75],[1.75,1.8,1.75]])
out['fixed_npc_keeper']={'positions':keeper_points.tolist(),'canopy_blocked':hit(keeper_points,tri).tolist(),
 'on_walkable_nav':False,'note':'Fixed NPC remains at approved anchor; player navigation exclusions do not change Mei. Face visible in opening; upper head is under existing canopy.'}
(folder/'validation.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in out.items() if k not in ['occlusion','routes']}),flush=True)
print('BLOCKERS',{k:v['count'] for k,v in blocked.items()},flush=True)
