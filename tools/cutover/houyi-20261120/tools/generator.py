"""Independent dynamic-farm generator. Source geometry -> core -> scene-local extension.
No game/Mapbox/provider imports; no service or gameplay writes.
"""
from __future__ import annotations
import collections,hashlib,json,math,re
import numpy as np
import shapely
from shapely.geometry import Polygon,box
from shapely.affinity import rotate,translate,affine_transform

DATASET='sf-dynamic-farm-20261118-r4'
VERSION='dynamic-core-ext-1'
PARAMS={'core_min':760,'core_max':840,'core_target':800,'min_width':4,'max_width':10,'noise_period':16,'total_limit':8192,'axis_limit':544,'cell_m':.8}
CAPS={'core':{'walk':True,'till':True,'plant':True,'arrange':True,'place':True},'extension':{'walk':True,'till':False,'plant':False,'arrange':False,'place':False}}
PALETTE=[{'id':0,'name':'Soil','color':'#D8BF8D'},{'id':1,'name':'Grass','color':'#8FAD69'},{'id':2,'name':'Path','color':'#BBA882'}]
class Rejected(ValueError):
 def __init__(self,reason,metrics=None,repairs=None):super().__init__(reason);self.reason=reason;self.metrics=metrics or {};self.repairs=repairs or []
def polygons(g):
 if g.is_empty:return []
 if g.geom_type=='Polygon':return [g]
 return [p for part in getattr(g,'geoms',[]) for p in polygons(part)]
def encode_runs(cells,surfaces=None):
 rows=collections.defaultdict(list)
 for x,y in cells:rows[int(y)].append(int(x))
 runs=[]
 for y in sorted(rows):
  xs=sorted(rows[y]);start=last=xs[0];kind=surfaces.get((start,y),1) if surfaces is not None else None
  for x in xs[1:]:
   k=surfaces.get((x,y),1) if surfaces is not None else None
   if x==last+1 and k==kind:last=x;continue
   runs.append([y,start,last-start+1]+([] if kind is None else [kind]));start=last=x;kind=k
  runs.append([y,start,last-start+1]+([] if kind is None else [kind]))
 return runs
def flood(cells,start=None):
 if not cells:return set()
 todo=[start or min(cells)];seen=set(todo)
 while todo:
  x,y=todo.pop()
  for q in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
   if q in cells and q not in seen:seen.add(q);todo.append(q)
 return seen
def components(cells):
 left=set(cells);n=0
 while left:
  seen=flood(left);left-=seen;n+=1
 return n
def cell_geometry(cells):
 xy=np.array(sorted(cells),dtype=np.int32)
 return shapely.coverage_union_all(shapely.box(xy[:,0],xy[:,1],xy[:,0]+1,xy[:,1]+1))
def boundary(g,origin):
 out=[]
 for p in sorted(polygons(g),key=lambda p:(-p.area,p.bounds)):
  p=p.simplify(.25,preserve_topology=True)
  ring=lambda rr:[[round(x-origin[0],4),round(y-origin[1],4)] for x,y in rr.coords]
  out.append({'outer':ring(p.exterior),'holes':[ring(h) for h in p.interiors]})
 return out
def noise(x,y,seed):
 period=PARAMS['noise_period'];gx=np.floor(x/period).astype(int);gy=np.floor(y/period).astype(int);fx=x/period-gx;fy=y/period-gy
 fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy)
 cache={}
 def value(ix,iy):
  k=(int(ix),int(iy))
  if k not in cache:cache[k]=int.from_bytes(hashlib.sha256((seed+':'+str(k[0])+':'+str(k[1])).encode()).digest()[:4],'big')/4294967295
  return cache[k]
 a=np.array([value(i,j) for i,j in zip(gx,gy)]);b=np.array([value(i+1,j) for i,j in zip(gx,gy)]);c=np.array([value(i,j+1) for i,j in zip(gx,gy)]);d=np.array([value(i+1,j+1) for i,j in zip(gx,gy)])
 return (a*(1-fx)+b*fx)*(1-fy)+(c*(1-fx)+d*fx)*fy

def preserves_source_topology(source, cells, h, x0, y0):
 parts=polygons(source)
 if len(parts)==1 and not parts[0].interiors:return True
 source=affine_transform(source,[1/h,0,0,1/h,-x0/h,-y0/h]);parts=polygons(source)
 core=cell_geometry(cells);targets=polygons(core);used_parts=set()
 for src in parts:
  choices=[(src.intersection(dst).area/src.area,i) for i,dst in enumerate(targets)]
  if not choices:return False
  coverage,index=max(choices)
  if coverage<.85 or index in used_parts:return False
  used_parts.add(index);dst=targets[index];used_holes=set()
  # Match only holes of the matched parent. Subtract ALL core islands from
  # target voids; a polygon's interior-ring area is not necessarily empty.
  for ring in src.interiors:
   void=Polygon(ring).difference(source)
   if void.is_empty:continue
   choices=[(void.intersection(Polygon(r).difference(core)).area/void.area,j) for j,r in enumerate(dst.interiors)]
   if not choices:return False
   retained,j=max(choices)
   if retained<.85 or j in used_holes:return False
   used_holes.add(j)
 return True

def core_from_geometry(g):
 flags=[]
 if not g.is_valid:g=shapely.make_valid(g);flags.append('make_valid')
 parts=polygons(g)
 if not parts:raise Rejected('invalid_geometry')
 g=shapely.union_all(parts)
 if g.area<1:raise Rejected('area_below_minimum',{'source_area_m2':g.area})
 best=None;topology_rejections=0;tried=['cell_size_search'];rotation_angles=[0.0]
 rect=g.minimum_rotated_rectangle;coords=list(rect.exterior.coords);edges=[(math.dist(coords[i],coords[i+1]),coords[i],coords[i+1]) for i in range(4)];long=max(edges,key=lambda e:e[0]);angle=math.degrees(math.atan2(long[2][1]-long[1][1],long[2][0]-long[1][0]));aligned=(-angle)%180
 if aligned>90:aligned-=180
 if abs(aligned)>.01:rotation_angles.append(aligned)
 for rotation in rotation_angles:
  if rotation and 'oriented_grid' not in tried:tried.append('oriented_grid')
  shape=rotate(g,rotation,origin=g.centroid) if rotation else g
  for px,py in [(0,0),(.5,0),(0,.5),(.5,.5)]:
   if (px or py) and 'phase_search' not in tried:tried.append('phase_search')
   h=math.sqrt(shape.area/800)
   for attempt in range(6):
    minx,miny,maxx,maxy=shape.bounds;x0=math.floor(minx/h-px)*h+px*h;y0=math.floor(miny/h-py)*h+py*h
    nx=math.ceil((maxx-x0)/h);ny=math.ceil((maxy-y0)/h)
    if max(nx,ny)>512 or nx*ny>262144:break
    xx,yy=np.meshgrid(np.arange(nx),np.arange(ny));xx=xx.ravel();yy=yy.ravel();squares=shapely.box(x0+xx*h,y0+yy*h,x0+(xx+1)*h,y0+(yy+1)*h)
    overlap=shapely.area(shapely.intersection(squares,shape));mask=overlap>=.5*h*h;n=int(mask.sum())
    if not n:break
    intersection=float(overlap[mask].sum());iou=intersection/(shape.area+n*h*h-intersection)
    if 760<=n<=840:
     candidate={'cells':set(zip(map(int,xx[mask]),map(int,yy[mask]))),'source_cell_m':h,'rotation_deg':rotation,'source_origin_m':[x0,y0],'iou':iou,'source_area_m2':g.area,'flags':flags+(['phase_shift'] if px or py else [])+(['oriented_grid'] if rotation else [])}
     if preserves_source_topology(shape,candidate['cells'],h,x0,y0):
      if best is None or iou>best['iou']:best=candidate
      if iou>=.9:return candidate
     else:topology_rejections+=1
    if 790<=n<=810:break
    h*=math.sqrt(n/800)
 if best is not None and best['iou']>=.85:
  best['flags'].append('approximation_warning');return best
 if best is None and topology_rejections:raise Rejected('core_shape_quality',{'topology_rejected_candidates':topology_rejections},tried+['source_component_hole_preservation'])
 if best is not None:raise Rejected('core_shape_quality',{'best_iou':best['iou'],'core_cell_count':len(best['cells'])},tried)
 raise Rejected('core_axis_budget' if max(g.bounds[2]-g.bounds[0],g.bounds[3]-g.bounds[1])/math.sqrt(g.area/800)>512 else 'core_cell_budget',repairs=tried)

def clean_address(value):
 if not isinstance(value,str):return None
 value=' '.join(value.split())
 if not value or re.search(r'\b(?:UNKNOWN|NONE|NULL)\b',value,re.IGNORECASE):return None
 return value

def build(block_id,core,metadata):
 C=core['cells'];assert 760<=len(C)<=840
 address=clean_address(metadata.get('address'));name=address or 'SF Parcel '+metadata['parcel_id']
 seed=hashlib.sha256((DATASET+':'+block_id+':'+VERSION+':'+json.dumps(PARAMS,sort_keys=True,separators=(',',':'))).encode()).hexdigest()
 geometry=cell_geometry(C);b=geometry.bounds;x0=int(b[0])-10;y0=int(b[1])-10;x1=int(b[2])+10;y1=int(b[3])+10
 W=x1-x0;H=y1-y0
 if max(W,H)>544:raise Rejected('extension_budget_exceeded',{'width':W,'height':H})
 xx,yy=np.meshgrid(np.arange(x0,x1),np.arange(y0,y1));xx=xx.ravel();yy=yy.ravel();pts=shapely.points(xx+.5,yy+.5);dist=shapely.distance(pts,geometry)
 values=noise(xx+.5,yy+.5,seed);E=set();chosen=(7,3)
 for base,amp in [(7,3),(6,2),(5,1),(4,0)]:
  keep=dist<=base+amp*(2*values-1);allcells=set(zip(map(int,xx[keep]),map(int,yy[keep])));allcells|=C
  if len(allcells)<=8192:E=allcells-C;chosen=(base,amp);break
 if not E:raise Rejected('extension_budget_exceeded',{'core_cell_count':len(C)})
 walk=C|E
 if len(flood(walk))!=len(walk):raise Rejected('walk_disconnected',{'core_components':components(C)})
 # Spawn in the core furthest from its boundary; tie-break by integer cell for determinism.
 corelist=sorted(C);cp=shapely.points([p[0]+.5 for p in corelist],[p[1]+.5 for p in corelist]);depth=shapely.distance(cp,geometry.boundary);spawn=corelist[int(np.argmax(depth))]
 # South-side exterior entry and a shortest 4-neighbor path to spawn. No current artwork collision baked in.
 entry=min(E,key=lambda p:(p[1],abs(p[0]-spawn[0]),p[0]));queue=collections.deque([entry]);previous={entry:None}
 while queue and spawn not in previous:
  x,y=queue.popleft()
  for n in [(x,y+1),(x-1,y),(x+1,y),(x,y-1)]:
   if n in walk and n not in previous:previous[n]=(x,y);queue.append(n)
 if spawn not in previous:raise Rejected('no_safe_spawn')
 path=set();q=spawn
 while q is not None:path.add(q);q=previous[q]
 reserve=set(C)
 for x,y,d in zip(xx,yy,dist):
  if d<=2 and (int(x),int(y)) in walk:reserve.add((int(x),int(y)))
 for x,y in path|{spawn,entry}:
  for dx in range(-2,3):
   for dy in range(-2,3):
    if dx*dx+dy*dy<=4 and (x+dx,y+dy) in walk:reserve.add((x+dx,y+dy))
 # All protected core pieces must remain connected even if decoration fills the unprotected extension.
 connected=flood(reserve,spawn)
 while len(connected)<len(reserve):
  goal=min(reserve-connected);queue=collections.deque([goal]);parents={goal:None};hit=None
  while queue:
   q=queue.popleft()
   if q in connected:hit=q;break
   for n in [(q[0]-1,q[1]),(q[0]+1,q[1]),(q[0],q[1]-1),(q[0],q[1]+1)]:
    if n in walk and n not in parents:parents[n]=q;queue.append(n)
  if hit is None:raise Rejected('no_safe_spawn')
  while hit is not None:
   x,y=hit
   for dx in range(-2,3):
    for dy in range(-2,3):
     if dx*dx+dy*dy<=4 and (x+dx,y+dy) in walk:reserve.add((x+dx,y+dy))
   hit=parents[hit]
  connected=flood(reserve,spawn)
 shift=lambda cells:{(x-x0,y-y0) for x,y in cells}
 cs=shift(C);es=shift(E);rs=shift(reserve);path_shift=shift(path)
 core_surface={p:0 for p in cs};ext_surface={p:(2 if p in path_shift else 1) for p in es}
 return {'schema':4,'dataset_version':DATASET,'selection_unit':'parcel','block_id':block_id,'parcel_id':metadata['parcel_id'],'parcel_aliases':metadata.get('parcel_aliases',[metadata['parcel_id']]),'name':name,'address':address, 'generator_version':VERSION,'seed_hex':seed,'game_cell_m':.8,'source_area_m2':core['source_area_m2'],'source_cell_m':core['source_cell_m'],'source_transform':{'crs':'EPSG:32610','rotation_deg':core['rotation_deg'],'origin_m':core.get('source_origin_m',[0,0])},'grid':{'width':W,'height':H,'origin_cell':[x0,y0]},'zones':{'core':{'runs':encode_runs(cs,core_surface)},'extension':{'runs':encode_runs(es,ext_surface)}},'capabilities':CAPS,'counts':{'core_cell_count':len(C),'extension_cell_count':len(E),'total_cell_count':len(walk)},'surface_palette':PALETTE,'boundaries':{'core':boundary(geometry,(x0,y0)),'outer':boundary(cell_geometry(walk),(x0,y0))},'walk_reserve':{'no_solid_decor_runs':encode_runs(rs),'spawn_cell':[spawn[0]-x0,spawn[1]-y0],'entry_cell':[entry[0]-x0,entry[1]-y0]},'geo_hints':metadata.get('geo_hints',{'water_fraction':0,'landuse':'unknown','source_building_count':0}),'stats':{'core_iou':core['iou'],'width_min_cells':chosen[0]-chosen[1],'width_max_cells':chosen[0]+chosen[1],'core_components':components(C),'walk_components':1,'recovery_flags':core['flags']+(['reduced_extension_width'] if chosen!=(7,3) else [])},'attribution':'DataSF / SF Planning (PDDL / CC0); scene extension is procedural'}
