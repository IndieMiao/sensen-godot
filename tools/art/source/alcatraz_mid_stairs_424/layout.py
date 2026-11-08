"""SGODOT-424 A: preserve approved island; add three central links and rebuild nav.
The 2026-11-08 clarification permits +Z 0.5m to keep flowerbeds fixed.
"""
from pathlib import Path
import json,math,copy
from collections import defaultdict
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];OUT=ROOT/'assets/landmarks/alcatraz_island'
BASE=json.loads((HERE/'baseline_layout.json').read_text());layout=copy.deepcopy(BASE);placements=layout['placements']
# Clear stair width1.8, run4.5, rise2.25. Platforms 1.25m along run and >=1.8m across.
FLIGHTS=[{'id':5,'low':3.25,'high':5.5,'z0':5.0,'z1':6.8,'east_up':True,'lower_road_edge':6.0,'upper_road_edge':4.5,'outer_rail_z':9.0},
 {'id':6,'low':5.5,'high':7.75,'z0':.5,'z1':2.3,'east_up':False,'lower_road_edge':1.5,'upper_road_edge':0.0,'outer_rail_z':4.5},
 {'id':7,'low':7.75,'high':10.0,'z0':-4.0,'z1':-2.2,'east_up':True,'lower_road_edge':-3.0,'upper_road_edge':-4.5,'outer_rail_z':0.0}]
for s in FLIGHTS:
 s['x0']=-3.5;s['x1']=1.;s['z']=(s['z0']+s['z1'])/2
 s['west_platform']=[-4.75,-3.5,s['z0'],s['z1']]
 s['east_platform']=[1.,2.25,s['z0'],s['z1']]
 s['lower_platform']=s['west_platform'] if s['east_up'] else s['east_platform']
 s['upper_platform']=s['east_platform'] if s['east_up'] else s['west_platform']
 # The upper landing reaches back to its road without cutting any planted beds.
 s['upper_platform'][2]=s['upper_road_edge']-.25
 s['upper_platform'][3]=s['z1']
 s['lower_mouth']=[s['lower_platform'][0],s['lower_platform'][1],s['z1'],s['low']]
 s['upper_mouth']=[s['upper_platform'][0],s['upper_platform'][1],s['upper_road_edge'],s['high']]
changes=[]
for p in placements:
 if p['name'] in ['alc_bench_000','alc_bench_002']:
  old=p['position'][:];p['position'][0]=-6.0;changes.append({'name':p['name'],'before':old,'after':p['position'][:]})
 if p['name']=='alc_bench_001':
  old=p['position'][:];p['position'][0]+=1;changes.append({'name':p['name'],'before':old,'after':p['position'][:]})
 if p['name']=='alc_bench_005':
  old=p['position'][:];p['position'][0]-=1.25;changes.append({'name':p['name'],'before':old,'after':p['position'][:]})
def segment(p):
 if 'basis_columns' in p:v=p['basis_columns'][0]
 else:v=[math.cos(p['yaw'])*p['scale'][0],0,-math.sin(p['yaw'])*p['scale'][0]]
 return [[p['position'][k]+sign*v[k] for k in range(3)] for sign in [-1,1]]
def set_segment(p,a,b):
 p['position']=[round((a[k]+b[k])/2,7) for k in range(3)]
 length=math.hypot(b[0]-a[0],b[2]-a[2]);yaw=math.atan2(-(b[2]-a[2]),b[0]-a[0]);p['scale']=[length/2,1,1];p['yaw']=yaw;p['rotation_degrees']=[0,math.degrees(yaw),0]
 for key in ['basis_columns','slope_rise_m']:p.pop(key,None)
 if abs(b[1]-a[1])>1e-6:
  p['basis_columns']=[[(b[k]-a[k])/2 for k in range(3)],[0,1,0],[math.sin(yaw),0,math.cos(yaw)]];p['slope_rise_m']=b[1]-a[1]
def new_placement(asset,name,at,zone='TerraceZone',collision=False,multi=True):
 return {'asset':asset,'name':name,'position':at,'zone':zone,'yaw':0,'rotation_degrees':[0,0,0],'scale':[1,1,1],'collision':collision,'multimesh':multi,'placeholder':False,'owner':'马可波罗'}
# Remove railing/curb portions which pass THROUGH the new ramp/platform footprint,
# plus the six mouths. Unchanged portions keep their source IDs and exact heights.
rail_changes=[];kept=[]
for p in placements:
 if p['asset'] not in ['alc_rail_straight','alc_curb']:
  kept.append(p);continue
 a,b=segment(p)
 if abs(a[2]-b[2])>.0001 or abs(a[1]-b[1])>.0001:
  kept.append(p);continue
 pieces=[(min(a[0],b[0]),max(a[0],b[0]))]
 for s in FLIGHTS:
  ranges=[]
  # Lower road's rear edge traverses the ramp: remove the full construction span.
  if abs(a[1]-s['low'])<.01 and abs(a[2]-s['lower_road_edge'])<.01:ranges=[(-4.75,2.25)]
  if abs(a[1]-s['high'])<.01 and abs(a[2]-s['upper_road_edge'])<.01:ranges.append(tuple(s['upper_platform'][:2]))
  for lo,hi in ranges:
   next_parts=[]
   for x0,x1 in pieces:
    if x1<=lo or x0>=hi:next_parts.append((x0,x1));continue
    if x0<lo:next_parts.append((x0,lo))
    if x1>hi:next_parts.append((hi,x1))
   pieces=next_parts
 if pieces==[(min(a[0],b[0]),max(a[0],b[0]))]:kept.append(p);continue
 rail_changes.append({'name':p['name'],'before':[a,b],'remaining':pieces})
 for i,(lo,hi) in enumerate(pieces):
  if hi-lo<.09:continue
  q=copy.deepcopy(p)
  if i:q['name']+='_split_'+str(i)
  set_segment(q,[lo,a[1],a[2]],[hi,a[1],a[2]]);kept.append(q)
placements[:]=kept
# Guard the ramp edges and landing's exposed outside ends; each prototype remains reusable.
for s in FLIGHTS:
 zone='TerraceZone'
 for side,z in [('north',s['z0']),('south',s['z1'])]:
  for i in range(3):
   x0=-3.5+i*1.5;x1=x0+1.5
   def hy(x):return s['low']+(x+3.5)/4.5*2.25 if s['east_up'] else s['high']-(x+3.5)/4.5*2.25
   for asset in ['alc_rail_straight','alc_curb']:
    p=new_placement(asset,f'mid{s["id"]}_{side}_{asset}_{i}',[0,0,0],zone,asset=='alc_rail_straight');set_segment(p,[x0,hy(x0),z],[x1,hy(x1),z]);placements.append(p)
 for kind,y in [('lower',s['low']),('upper',s['high'])]:
  plat=s[kind+'_platform'];x0,x1,z0,z1=plat
  # Ends off the original rail line use a matching standalone terminal post.
  mouth=s[kind+'_mouth']
  for side,x in [('west',x0-.11),('east',x1+.11)]:
   placements.append(new_placement('alc_railing_endpost',f'mid{s["id"]}_{kind}_{side}_endpost',[x,y,mouth[2]-(.01 if kind=='lower' else 0)],'SummitZone' if y==10 else 'TerraceZone',True,False))
  # Front lip protects the upper platform over the lower road; lower has open south entry.
  if kind=='upper':
   for asset in ['alc_rail_straight','alc_curb']:
    p=new_placement(asset,f'mid{s["id"]}_{kind}_{asset}_lip',[0,0,0],zone,asset=='alc_rail_straight');set_segment(p,[x0,y,z1],[x1,y,z1]);placements.append(p)
  x=x0 if x1<0 else x1
  for asset in ['alc_rail_straight','alc_curb']:
   p=new_placement(asset,f'mid{s["id"]}_{kind}_{asset}_end',[0,0,0],zone,asset=='alc_rail_straight');set_segment(p,[x,y,z0],[x,y,z1]);placements.append(p)
# Existing runtime merge hook gives new sheared guards their real triangle collision,
# avoiding the legacy oversized box used for sloping MultiMesh rails. Prototypes
# and point transforms remain independent in the placement contract.
for p in placements:
 if p['name'].startswith('mid'):
  p['render_merge_into']='alc_ground_terraces';p['multimesh']=True
placements.append(new_placement('alc_mid_stairs','alc_mid_stairs_000',[0,0,0],'TerraceZone',True,False))
# Existing authored surfaces; only the new construction overrides them.
flats=[(-23.5,-20.5,13.5,20,1),(-24,-18,10.5,14,1),(-23.5,9.5,6,9,3.25),(-23.5,9.5,1.5,4.5,5.5),(-23.5,9.5,-3,0,7.75),(-28,28,-8,-4.5,10)]
old_stairs=[(-23.5,-20.5,7.5,12,3.25,1),(6.5,9.5,3,7.5,5.5,3.25),(-23.5,-20.5,-1.5,3,7.75,5.5),(6.5,9.5,-6,-1.5,10,7.75)]
def within(x,z,r):return r[0]-1e-5<=x<=r[1]+1e-5 and r[2]-1e-5<=z<=r[3]+1e-5
def surface(x,z):
 for s in FLIGHTS:
  if within(x,z,[s['x0'],s['x1'],s['z0'],s['z1']]):return s['low']+(x+3.5)/4.5*2.25 if s['east_up'] else s['high']-(x+3.5)/4.5*2.25
  for kind,y in [('lower',s['low']),('upper',s['high'])]:
   if within(x,z,s[kind+'_platform']):return y
 for x0,x1,z0,z1,hi,lo in old_stairs:
  if within(x,z,[x0,x1,z0,z1]):return hi+(lo-hi)*(z-z0)/(z1-z0)
 for x0,x1,z0,z1,y in flats:
  if within(x,z,[x0,x1,z0,z1]):return y
 return None
def zone_for(y):return 'DockZone' if y<1.01 else 'SummitZone' if y>=9.99 else 'TerraceZone'
props=[p for p in placements if p['asset'] in ['alc_bench','alc_lamp','alc_sign','alc_planter','alc_bin','alc_flowerbed','alc_railing_endpost']]
def blocked(x,z):
 y=surface(x,z)
 for p in props:
  px,py,pz=p['position']
  if y is None or abs(y-py)>.3:continue
  asset=p['asset']
  if asset=='alc_bench' and abs(x-px)<1 and abs(z-pz)<.6:return True
  if asset in ['alc_lamp','alc_sign'] and math.hypot(x-px,z-pz)<.35:return True
  if asset=='alc_planter' and abs(x-px)<.6 and abs(z-pz)<.6:return True
  if asset=='alc_bin' and abs(x-px)<.5 and abs(z-pz)<.5:return True
  if asset=='alc_flowerbed' and abs(x-px)<1.1 and abs(z-pz)<1.1:return True
  if asset=='alc_railing_endpost' and abs(x-px)<.11 and abs(z-pz)<.12:return True
 return False
verts=[];polys=[];cells={};indices={};step=.25
for ix in range(-120,120):
 for iz in range(-80,81):
  x,z=ix*step,iz*step;heights=[surface(x+dx,z+dz) for dx,dz in [(0,0),(step,0),(step,step),(0,step)]]
  if any(y is None for y in heights) or surface(x+.125,z+.125) is None or blocked(x+.125,z+.125):continue
  if max(heights)-min(heights)>.15001:continue
  ids=[]
  for (vx,vz),y in zip([(ix,iz),(ix+1,iz),(ix+1,iz+1),(ix,iz+1)],heights):
   key=(vx,round(y,5),vz)
   if key not in indices:indices[key]=len(verts);verts.append([vx*step,round(y,5),vz*step])
   ids.append(indices[key])
  cells[(ix,iz)]=len(polys);polys.append(list(reversed(ids)))
retained={p:i for p,i in cells.items() if all(q in cells for q in [(p[0]+1,p[1]),(p[0]-1,p[1]),(p[0],p[1]+1),(p[0],p[1]-1)])}
# Connected components are evidence; don't silently discard a disconnected new landing.
remaining=set(retained);components=[]
while remaining:
 seen=set();todo=[next(iter(remaining))]
 while todo:
  p=todo.pop()
  if p in seen:continue
  seen.add(p);todo.extend(q for q in [(p[0]+1,p[1]),(p[0]-1,p[1]),(p[0],p[1]+1),(p[0],p[1]-1)] if q in remaining and q not in seen)
 remaining-=seen;components.append(seen)
components.sort(key=len,reverse=True)
assert sum(len(c) for c in components[1:])<=8, [len(c) for c in components]
keep=components[0];polys=[polys[i] for p,i in retained.items() if p in keep]
# Replace the ramp proxy cells with actual horizontal treads and vertical risers.
# Godot's .25/.1 map supports these connected faces; feet follow the visible steps.
polys=[p for p in polys if not any(s['x0']-1e-6<sum(verts[i][0] for i in p)/len(p)<s['x1']+1e-6 and s['z0']<sum(verts[i][2] for i in p)/len(p)<s['z1'] for s in FLIGHTS)]
def add_poly(points):
 ids=[]
 for x,y,z in points:
  key=(round(x,6),round(y,6),round(z,6))
  # Explicit face vertices share coordinates with the raster landing boundaries.
  ids.append(len(verts));verts.append(list(key))
 polys.append(ids)
# Co-planar floor raster cells are triangulated as their exact union, preserving
# holes and all stair seam vertices. This removes grid-edge detours without
# changing a single walkable square or expanding any clearance boundary.
from shapely.geometry import Polygon,box as shapely_box
from shapely.ops import unary_union
from shapely import constrained_delaunay_triangles
flat_groups=defaultdict(list);slope_polys=[];seams=defaultdict(set)
for poly in polys:
 ys=[verts[i][1] for i in poly]
 if max(ys)-min(ys)<1e-7:flat_groups[round(ys[0],5)].append(Polygon([(verts[i][0],verts[i][2]) for i in poly]))
 else:
  slope_polys.append(poly)
  for i in poly:seams[round(verts[i][1],5)].add((verts[i][0],verts[i][2]))
for st in FLIGHTS:
 za=math.ceil((st['z0']+.5)/.25)*.25;zb=math.floor((st['z1']-.5)/.25)*.25
 for y,x in [(st['low'],st['x0'] if st['east_up'] else st['x1']),(st['high'],st['x1'] if st['east_up'] else st['x0'])]:
  seams[y].update([(x,za),(x,zb)])
def seam_ring(ring,points):
 coords=list(ring.coords);out=[]
 for a,b in zip(coords,coords[1:]):
  out.append(a);dx,dz=b[0]-a[0],b[1]-a[1];sq=dx*dx+dz*dz;on=[]
  for x,z in points:
   t=((x-a[0])*dx+(z-a[1])*dz)/sq
   if 1e-7<t<1-1e-7 and abs((x-a[0])*dz-(z-a[1])*dx)<1e-7:on.append((t,(x,z)))
  out.extend(p for _,p in sorted(on))
 return out
polys=slope_polys
for y,group in sorted(flat_groups.items()):
 union=unary_union(group)
 for st in FLIGHTS:
  if abs(y-st['low'])>.01:continue
  x0=st['x0'] if st['east_up'] else st['upper_platform'][0]
  x1=st['upper_platform'][1] if st['east_up'] else st['x1']
  # Keep >=1.5m in the LIVE nav, accounting for .09m rails and .25m actor radius.
  lo=st['z1']+.10+.25;hi=st['outer_rail_z']-.09-.25
  assert hi-lo>=1.5-1e-6
  union=union.difference(shapely_box(x0,st['z1']+.001,x1,st['outer_rail_z'])).union(shapely_box(x0,lo,x1,hi))
 union=union.simplify(.000001,preserve_topology=True)
 for region in [union] if union.geom_type=='Polygon' else union.geoms:
  fixed=Polygon(seam_ring(region.exterior,seams[y]),[seam_ring(r,seams[y]) for r in region.interiors])
  for triangle in constrained_delaunay_triangles(fixed).geoms:
   coords=list(triangle.exterior.coords)[:-1]
   area=sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(coords,coords[1:]+coords[:1]))
   if area>0:coords.reverse()
   add_poly([(x,y,z) for x,z in coords])
for s in FLIGHTS:
 z0=math.ceil((s['z0']+.5)/.25)*.25;z1=math.floor((s['z1']-.5)/.25)*.25
 for i in range(15):
  xa=s['x0']+i*.3 if s['east_up'] else s['x1']-i*.3
  xb=xa+.3 if s['east_up'] else xa-.3;low=s['low']+i*.15;high=low+.15
  for iz in range(1):
   za=z0;zb=z1
   add_poly([(min(xa,xb),high,za),(min(xa,xb),high,zb),(max(xa,xb),high,zb),(max(xa,xb),high,za)])
   add_poly([(xa,low,za),(xa,low,zb),(xa,high,zb),(xa,high,za)] if s['east_up'] else [(xa,low,zb),(xa,low,za),(xa,high,za),(xa,high,zb)])
navzones={z:[] for z in BASE['zones']}
for poly in polys:navzones[zone_for(sum(verts[i][1] for i in poly)/4)].append(poly)
layout['navigation']={'vertices':verts,'polygons':polys,'zone_polygons':navzones,'cell':step};layout['nav_connected_cells']=len(polys)
route=[[-22,1,19],[-22,1,12],[-22,3.25,7.5],[-4.125,3.25,7.5]]
for s in FLIGHTS:
 lo=s['lower_platform'];up=s['upper_platform'];lx=(lo[0]+lo[1])/2;ux=(up[0]+up[1])/2
 route += [[lx,s['low'],s['z']],[s['x0'] if s['east_up'] else s['x1'],s['low'],s['z']],
 [s['x1'] if s['east_up'] else s['x0'],s['high'],s['z']],[ux,s['high'],s['z']],[ux,s['high'],s['upper_road_edge']-.75]]
route += [[0,10,-6]]
verified=HERE/'route_verified.json'
if verified.exists():
 import hashlib
 evidence=json.loads(verified.read_text());digest=hashlib.sha256(json.dumps(layout['navigation'],sort_keys=True).encode()).hexdigest()
 assert evidence['navigation_sha256']==digest,'Regenerate runtime route evidence after navigation changes'
 route=evidence['centerline_path']
layout['route']=route;layout['route_centerline_m']=sum(math.dist(a,b) for a,b in zip(route,route[1:]));layout['walk_goals']=[layout['spawn']]+evidence['goals'] if verified.exists() else [route[0]]+[r for r in route[4:]]
if verified.exists():layout['route_measurement']={'centerline_basis':'existing convention: straight sloped span across each flight','runtime_tread_path_m':evidence['runtime_tread_path_m'],'runtime_goals':evidence['goals']}
layout['review_points'].update({'mid_hill':[-1.25,6.7,1.4],'visitor_center':[0,10,-6],'mid_stair_low':[-1.85,4.15,5.5],'mid_stair_high':[-1.85,8.65,-3.5]})
for s in FLIGHTS:layout['stairs'].append({'flight':s['id'],'lower':s['low'],'upper':s['high'],'width':1.8,'run':4.5,'risers':15,'riser_m':.15,'x':[-3.5,1],'z':[s['z0'],s['z1']],'ascent':'east' if s['east_up'] else 'west','lower_platform':s['lower_platform'],'upper_platform':s['upper_platform']})
layout['mid_stairs']={'approval':'SGODOT-424 sketch A + 2026-11-08 +Z 0.5m clearance clarification','flights':FLIGHTS,'prop_moves':changes,'rail_cuts':rail_changes,'original_route':BASE['route'],'original_route_centerline_m':BASE['route_centerline_m'],'opening_count':6,'endpost_count':12,'physical_lower_road_clearance_m':2.01,'actor_center_clearance_m':1.51,'front_guard_extent_m':.10,'stair_nav_edge_inset_m':.5}
layout['render_groups']['mid_stair_sides']='new guard rails, curbs and terminal posts merge into alc_ground_terraces with exact triangle collision; prototypes/points retained'
layout['ground_materials']['alc_mid_stairs']='ground/alc_terrain_detail.tres'
for name in ['alc_mid_stairs','alc_railing_endpost']:layout['assets'].append({'name':name,'file':name+'.glb','placeholder':False,'owner':'马可波罗','pivot':'island origin' if name=='alc_mid_stairs' else 'ground centre','cast_shadow':name=='alc_mid_stairs','material':'vertex_color'})
layout['instances']=[{k:p[k] for k in ['name','asset','zone','position','rotation_degrees','scale','basis_columns','slope_rise_m','owner','placeholder','source_name','support_y_offset_m','surface_group'] if k in p} for p in placements if p['multimesh']]
byname={p['name']:p for p in placements}
for p in layout['interest_points']:
 if p['name'] in byname:p['position']=byname[p['name']]['position'][:]
used={i for p in polys for i in p};layout['walk_bounds'].update({'min':[min(verts[i][k] for i in used) for k in range(3)],'max':[max(verts[i][k] for i in used) for k in range(3)]})
if __name__=='__main__':
 (OUT/'layout.json').write_text(json.dumps(layout,separators=(',',':'))+'\n')
 (OUT/'placement_points.json').write_text(json.dumps({'units':'metres','axes':layout['axes'],'instances':layout['instances']},ensure_ascii=False,indent=2)+'\n')
 (HERE/'construction.json').write_text(json.dumps({'flights':FLIGHTS,'moves':changes,'rail_cuts':rail_changes,'nav_components':[len(c) for c in components],'route_centerline_m':layout['route_centerline_m']},ensure_ascii=False,indent=2)+'\n')
 print('MID_STAIRS_LAYOUT',len(polys),'cells, route',layout['route_centerline_m'],'components',[len(c) for c in components])
