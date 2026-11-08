"""Audit live navigation samples against transformed tree triangles; no game writes."""
from pathlib import Path
import json,math,sys
import numpy as np
folder=Path(sys.argv[1]);r=json.loads((folder/'review.json').read_text());points=np.array(r['nav_samples']);origins=np.repeat(points,2,axis=0);origins[:,1]+=np.tile([1.0,1.6],len(points))
yaw=math.radians(14.5);pitch=math.radians(43);direction=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch)])
def hits(points,tri):
 v=tri[:,0];a=tri[:,1]-v;b=tri[:,2]-v;cross=np.cross(direction,b);det=np.einsum('ij,ij->i',a,cross);valid=np.abs(det)>1e-9
 v,a,b,cross,det=[q[valid] for q in [v,a,b,cross,det]];result=np.zeros(len(points),bool)
 for i in range(0,len(points),32):
  s=points[i:i+32,None,:]-v[None,:,:];u=np.einsum('ptj,tj->pt',s,cross)/det;q=np.cross(s,a);z=np.einsum('ptj,j->pt',q,direction)/det;t=np.einsum('ptj,tj->pt',q,b)/det
  result[i:i+32]=((u>=-1e-7)&(z>=-1e-7)&(u+z<=1+1e-7)&(t>1e-5)).any(axis=1)
 return result
route_path=np.array(r['runtime_path']);lengths=np.linalg.norm(np.diff(route_path,axis=0),axis=1);cum=np.r_[0,np.cumsum(lengths)];route_points=[]
for d in np.arange(0,cum[-1]+1e-7,.5):
 i=min(len(lengths)-1,max(0,np.searchsorted(cum,d,side='right')-1));route_points.append(route_path[i]+(route_path[i+1]-route_path[i])*((d-cum[i])/lengths[i] if lengths[i]>1e-8 else 0))
route_points=np.array(route_points);route_origins=np.repeat(route_points,2,axis=0) if len(route_points) else np.empty((0,3))
if len(route_origins):route_origins[:,1]+=np.tile([1.0,1.6],len(route_points))
route_blocked={}
blocked={}
for m in r['tree_meshes']:
 tri=np.array(m['faces']).reshape(-1,3,3);lo=tri.min(axis=(0,1));hi=tri.max(axis=(0,1));center=(lo+hi)/2;radius=np.linalg.norm(tri.reshape(-1,3)-center,axis=1).max();v=center-origins;along=v@direction;cross=np.einsum('ij,ij->i',v,v)-along**2;ids=np.where((cross<=radius**2)&(along+radius>0))[0];ids=ids[hits(origins[ids],tri)]
 if len(ids):blocked[m['name']]={'indices':ids.tolist(),'points':origins[ids].tolist(),'count':len(ids)}
 if len(route_origins):
  v=center-route_origins;along=v@direction;cross=np.einsum('ij,ij->i',v,v)-along**2;ids=np.where((cross<=radius**2)&(along+radius>0))[0];ids=ids[hits(route_origins[ids],tri)]
  if len(ids):route_blocked[m['name']]={'indices':ids.tolist(),'points':route_origins[ids].tolist()}
foot=r['walk'].get('foot_samples',[]);interior=[p for p in foot if min((p['position'][0]+3.5)%.3,.3-(p['position'][0]+3.5)%.3)>.03]
summary={'layout_path_length_m':r['layout_path_length'],'p0_path_length_m':r['runtime_path_length'],'walk_end_error_m':r['walk']['error_m'],'nav_samples_05m':len(points),'tree_blocked_sample_count':len({i//2 for m in blocked.values() for i in m['indices']}),'tree_blockers':blocked,'route_samples_05m':len(route_points),'route_tree_blocked_sample_count':len({i//2 for m in route_blocked.values() for i in m['indices']}),'route_tree_blockers':route_blocked,'hud_samples':len(r['walk'].get('trace_05m',[])) or r['walk']['hud_samples'],'hud_failures':r['walk']['hud_failures'],'openings':r['openings'],'tread_foot_sample_count':len(interior),'tread_max_abs_y_error_m':max((abs(p['delta_y']) for p in interior),default=0),'stair_click':r.get('stair_click')}
(folder/'validation.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in summary.items() if k not in ['tree_blockers','hud_failures','openings']},ensure_ascii=False));print('TREE_BLOCKERS',{k:v['count'] for k,v in blocked.items()});print('HUD_FAILURES',len(summary['hud_failures']))
