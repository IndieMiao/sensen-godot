"""SGODOT-424 v2: real-metre blockout, 60 x 40 m island and ~120 m route.
Run Blender through ~/gs66-render.lock. Full rebuild overwrites the editable source.
"""
from pathlib import Path
from collections import defaultdict
import json, math, random, sys
import bpy
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[3]
sys.path.insert(0,str(ROOT/'tools/art'))
from landmark_kit import Kit,reset_scene
OUT=ROOT/'assets/landmarks/alcatraz_island'
reset_scene(); random.seed(424)
kit=Kit(OUT,{'stone':'b5b6b3','garden':'8d9690','road':'e5e3db','building':'dbdcd7',
 'roof':'acb1b2','glass':'78868a','wood':'b8b3a6','dark':'727d80','bird':'eeede6','bridge':'c76845','far':'b4c2c8'})
placements=[]
ZONES=['DockZone','TerraceZone','SummitZone']
def place(asset,pos=(0,0,0),zone='TerraceZone',yaw=0,scale=1,collision=True):
 placements.append(dict(asset=asset,position=list(pos),zone=zone,yaw=yaw,scale=scale,collision=collision))
def box(n,p,s,c='building',bevel=.02):return kit.box(n,p,s,c,bevel)
def prism(n,poly,lo,hi,c):
 if sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(poly,poly[1:]+poly[:1]))>0:poly=list(reversed(poly))
 count=len(poly);v=[(x,y,z) for y in [lo,hi] for x,z in poly]
 faces=[tuple(reversed(range(count))),tuple(range(count,2*count))]
 faces.extend((i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count))
 return kit.mesh(n,v,faces,c)
# Terrain meshes are split at actual loading-zone boundaries; pivots remain the island origin.
# Stair corridors are outside the higher terrace lip. Paved ledges get real retaining supports.
bands=[('DockZone',-.6,1,[(-24,14),(-25,7.5),(24,7.5),(24,14)]),
 ('TerraceZone',-.6,3.25,[(-25,7.5),(-27,3),(27,3),(25,7.5)]),
 ('TerraceZone',-.6,5.5,[(-27,3),(-29,-1.5),(29,-1.5),(27,3)]),
 ('TerraceZone',-.6,7.75,[(-29,-1.5),(-30,-6),(30,-6),(29,-1.5)]),
 ('SummitZone',-.6,10,[(-30,-6),(-30,-17),(-27,-20),(27,-20),(30,-17),(30,-6)])]
for zone in ZONES:
 kit.begin('terrain_'+zone,ao=False)
 for i,(z,lo,hi,poly) in enumerate(bands):
  if z!=zone:continue
  prism('cliff_band_%d'%i,list(reversed(poly)),lo,hi-.15,'stone')
  prism('garden_band_%d'%i,list(reversed(poly)),hi-.15,hi,'garden')
 place('terrain_'+zone,zone=zone)
# Rectangle surfaces (x0,x1,z0,z1,height,zone). Stair cuts are subtracted before meshing.
flats=[(-23.5,-20.5,13.5,20,1,'DockZone'),(-24,-18,10.5,14,1,'DockZone'),
 (-23.5,9.5,6,9,3.25,'TerraceZone'),(-23.5,9.5,1.5,4.5,5.5,'TerraceZone'),
 (-23.5,9.5,-3,0,7.75,'TerraceZone'),(-28,28,-8,-4.5,10,'SummitZone')]
stairs=[(-23.5,-20.5,7.5,12,3.25,1), (6.5,9.5,3,7.5,5.5,3.25),
 (-23.5,-20.5,-1.5,3,7.75,5.5),(6.5,9.5,-6,-1.5,10,7.75)]
def subtract_rect(r,cut):
 x0,x1,z0,z1=r;a,b,c,d=cut
 if x1<=a or x0>=b or z1<=c or z0>=d:return [r]
 out=[]
 if x0<a:out.append((x0,a,z0,z1))
 if x1>b:out.append((b,x1,z0,z1))
 left=max(x0,a);right=min(x1,b)
 if z0<c:out.append((left,right,z0,c))
 if z1>d:out.append((left,right,d,z1))
 return out
for zone in ZONES:
 kit.begin('walkways_'+zone,ao=False)
 for i,(x0,x1,z0,z1,y,z) in enumerate(flats[1:]):
  if z!=zone:continue
  parts=[(x0,x1,z0,z1)]
  for a,b,c,d,hi,lo in stairs:
   if abs(y-hi)<.01:parts=[p for r in parts for p in subtract_rect(r,(a,b,c,d))]
  for a,b,c,d in parts:
   box('paving_%d'%i,((a+b)/2,y-.105,(c+d)/2),(b-a,.25,d-c),'road',.01)
   if y>1:box('retaining_support_%d'%i,((a+b)/2,(y+max(1,y-2.25))/2-.13,(c+d)/2),(b-a,y-max(1,y-2.25),d-c),'stone',0)
 place('walkways_'+zone,zone=zone)
for j,(x0,x1,z0,z1,hi,lo) in enumerate(stairs):
 name='stairs_%d'%(j+1);kit.begin(name,ao=False)
 for i in range(15):
  y=hi-i*.15
  box('flight_%d_riser_%02d'%(j+1,i),((x0+x1)/2,(y+lo-.18)/2,z0+(i+.5)*.3),(x1-x0,y-lo+.22,.303),'road',.006)
 place(name,zone='TerraceZone')
kit.begin('dock',ao=False)
box('continuous_deck_subfloor',(0,-.16,0),(3,.12,6.5),'wood',0)
for i in range(26):box('deck_%02d'%i,(0,-.1,-3.25+(i+.5)*.25),(3,.2,.238),'wood',.008)
for x in [-1.6,1.6]:
 for z in [-1.5,1.5,3.1]:box('pile',(x,-.45,z),(.22,2.9,.22),'wood',.01)
place('dock',(-22,1,16.75),'DockZone')
# Accurate public-building envelope: x=40, z=10, y=9, no prison detailing.
kit.begin('visitor_center',ao=False)
box('museum_two_storeys',(0,4.4,0),(40,8.8,10),'building',.05)
box('roof',(0,8.9,0),(40,.2,10),'roof',.02)
box('public_door_frame',(0,1.8,5.1),(2.6,3.6,.2))
box('public_glazed_door',(0,1.65,5.22),(1.8,3.3,.04),'glass',0)
for x in range(-18,19,3):
 for y in [2.3,6.3]:
  if x==0 and y<3:continue
  box('unbarred_window',(x,y,5.03),(1.25,2.15,.04),'glass',.04)
for x in [-19.6,19.6]:box('corner_trim',(x,4.4,5.06),(.4,8.8,.12))
place('visitor_center',(0,10,-13),'SummitZone')
kit.begin('lighthouse',ao=False)
kit.cylinder('tower',(0,6.1,0),1.55,12.2,'building',top=1.0,seg=20)
kit.cylinder('gallery',(0,12.35,0),1.85,.3,'road',seg=20)
kit.cylinder('lantern',(0,13.3,0),1.05,1.6,'glass',seg=16)
kit.cylinder('cap',(0,14.55,0),1.4,.9,'building',top=0,seg=20)
place('lighthouse',(-25,10,-11.5),'SummitZone')
kit.begin('water_tower',ao=False)
for x in [-1.7,1.7]:
 for z in [-1.7,1.7]:kit.beam('leg',(x*1.3,0,z*1.3),(x,8,z),.22,'wood')
for z in [-1.7,1.7]:
 kit.beam('brace',(-1.7,.4,z),(1.7,7.8,z),.15,'wood')
 kit.beam('brace',(1.7,.4,z),(-1.7,7.8,z),.15,'wood')
kit.cylinder('tank',(0,9.5,0),2.5,3,'wood',seg=20)
kit.cylinder('tank_cap',(0,11.5,0),2.7,1,'roof',top=0,seg=20)
place('water_tower',(25,10,-14),'SummitZone')
kit.begin('ruins',ao=False)
for x,h in [(-4,3),(-2,4),(0,4.5),(2,3.5),(4,2.5)]:box('remaining_pier',(x,h/2,0),(.5,h,.45),'stone')
box('lintel',(-1,3.2,0),(7,.4,.45),'stone');box('side_wall',(4,1,-2),(.45,2,4),'stone')
place('ruins',(16,3.25,5),'TerraceZone')
kit.begin('ferry',ao=False)
prism('hull',[(-12.5,0),(-10.4,-3.1),(12.5,-3.1),(12.5,3.1),(-10.4,3.1)],-1,1.1,'building')
box('deck',(1,1.35,0),(20,.5,6))
box('cabin',(2.3,3.15,0),(15,3.1,4.5))
box('roof',(2.3,4.8,0),(15.4,.2,4.9),'roof')
for z in [-2.27,2.27]:
 for x in range(-4,10,2):box('ferry_window',(x,3.5,z),(1.15,1.3,.04),'glass',.03)
kit.cylinder('funnel',(6,5.7,0),.6,1.6,'dark',seg=12)
place('ferry',(-7,0,19),'DockZone',collision=False)
kit.begin('bench',ao=False)
box('seat',(0,.395,0),(1.5,.11,.48),'wood',.015)
box('back',(0,.73,-.21),(1.5,.56,.10),'wood',.015)
for x in [-.55,.55]:box('leg',(x,.17,0),(.10,.34,.40),'dark',.01)
for pos,zone in [((-19,1,13),'DockZone'),((-7,3.25,8.5),'TerraceZone'),((-7,5.5,4),'TerraceZone'),
 ((-7,7.75,-2.5),'TerraceZone'),((-10,10,-7),'SummitZone'),((15,10,-7),'SummitZone')]:place('bench',pos,zone)
kit.begin('lamp',ao=False)
kit.cylinder('post',(0,1.6,0),.07,3.2,'dark',seg=10)
kit.ellipsoid('globe',(0,3.35,0),(.30,.30,.30),'bird',seg=10,rings=6)
for p,z in [((-18.5,1,11),'DockZone'),((-18,3.25,6.3),'TerraceZone'),((7,3.25,8.7),'TerraceZone'),
 ((-18,5.5,1.8),'TerraceZone'),((7,5.5,4.2),'TerraceZone'),((-18,7.75,-2.7),'TerraceZone'),
 ((-6,10,-7),'SummitZone'),((18,10,-7),'SummitZone')]:place('lamp',p,z)
kit.begin('gull',ao=False)
kit.ellipsoid('body',(0,.12,0),(.32,.24,.45),'bird',seg=10,rings=6)
kit.ellipsoid('head',(0,.29,-.18),(.19,.19,.19),'bird',seg=8,rings=6)
box('beak',(0,.28,-.29),(.08,.06,.13),'wood',.01)
for p,z in [((-23.6,2,18.2),'DockZone'),((10,4.25,8.7),'TerraceZone'),((-24,11,-7),'SummitZone')]:place('gull',p,z,collision=False)
# Scenery is authored separately, rendered by a distant-scene viewport, not placed in the walkable world.
kit.begin('golden_gate_backdrop',ao=False)
box('deck',(0,.45,0),(3.4,.08,.22),'bridge',.01)
for x in [-.95,.95]:
 for z in [-.11,.11]:box('tower',(x,.85,z),(.11,1.7,.10),'bridge',.01)
 for y in [.6,1.2,1.6]:box('crossbeam',(x,y,0),(.14,.08,.36),'bridge',.01)
for z in [-.16,.16]:
 pts=[]
 for i in range(33):
  x=-1.7+i*3.4/32;y=.65+.95*(abs(x)/.95)**2 if abs(x)<.95 else 1.6-(abs(x)-.95)*1.25
  pts.append((x,y,z))
 for a,b in zip(pts,pts[1:]):kit.beam('cable',a,b,.025,'bridge')
 for i in range(15):
  x=-1.6+i*3.2/14;y=.65+.95*(abs(x)/.95)**2 if abs(x)<.95 else 1.6-(abs(x)-.95)*1.25
  kit.beam('hanger',(x,.49,z),(x,y,z),.018,'bridge')
place('golden_gate_backdrop',(-6.7,0,-23),'DistantScenery',scale=1.5,collision=False)
kit.begin('city_backdrop',ao=False)
for i in range(38):
 x=-35+i*1.8;h=random.uniform(1,3.3)
 box('skyline_%02d'%i,(x,h/2,random.uniform(-1,1)),(random.uniform(.8,1.5),h,1.3),'far',0)
kit.cylinder('transamerica',(2,3.4,0),.65,6.8,'far',top=0,seg=4)
place('city_backdrop',(12,0,-24),'DistantScenery',scale=.4,collision=False)

def surface(x,z):
 for x0,x1,z0,z1,hi,lo in stairs:
  if x0-1e-5<=x<=x1+1e-5 and z0-1e-5<=z<=z1+1e-5:return hi+(lo-hi)*(z-z0)/(z1-z0)
 for x0,x1,z0,z1,y,zone in flats:
  if x0-1e-5<=x<=x1+1e-5 and z0-1e-5<=z<=z1+1e-5:return y
 return None
def zone_for(x,z,y):return 'DockZone' if y<1.01 else 'SummitZone' if y>=9.99 else 'TerraceZone'
def blocked(x,z):
 for p in placements:
  px,py,pz=p['position']
  if p['asset']=='bench' and abs(x-px)<1 and abs(z-pz)<.6:return True
  if p['asset']=='lamp' and math.hypot(x-px,z-pz)<.35:return True
 return False
verts=[];polys=[];cells={};index={};step=.25
for ix in range(-120,120):
 for iz in range(-80,81):
  x,z=ix*step,iz*step
  heights=[surface(x+dx,z+dz) for dx,dz in [(0,0),(step,0),(step,step),(0,step)]]
  if any(y is None for y in heights) or surface(x+.125,z+.125) is None or blocked(x+.125,z+.125):continue
  if max(heights)-min(heights)>.15:continue
  ids=[]
  for (vx,vz),y in zip([(ix,iz),(ix+1,iz),(ix+1,iz+1),(ix,iz+1)],heights):
   key=(vx,round(y,5),vz)
   if key not in index:index[key]=len(verts);verts.append([vx*step,round(y,5),vz*step])
   ids.append(index[key])
  cells[(ix,iz)]=len(polys);polys.append(list(reversed(ids)))
walk_cells=cells.copy()
retained={p:i for p,i in cells.items() if all(q in cells for q in [(p[0]+1,p[1]),(p[0]-1,p[1]),(p[0],p[1]+1),(p[0],p[1]-1)])}
polys=[polys[i] for i in retained.values()];cells={p:i for i,p in enumerate(retained)}
# Merge the boundary into long runs, then build true 1 m rails with modest geometry.
edges=defaultdict(list)
for ix,iz in walk_cells:
 x,z=(ix+.5)*step,(iz+.5)*step;y=surface(x,z);zone=zone_for(x,z,y)
 if z>19.5:continue
 for dx,dz in [(1,0),(-1,0),(0,1),(0,-1)]:
  if (ix+dx,iz+dz) in walk_cells:continue
  # Do not fence small notches around benches/lamp posts.
  if blocked(x+dx*step,z+dz*step):continue
  if dx:
   edges[(zone,'z',round(x+dx*step/2,4),round(y,4))].append((z-step/2,z+step/2))
  else:edges[(zone,'x',round(z+dz*step/2,4),round(y,4))].append((x-step/2,x+step/2))
for zone in ZONES:
 kit.begin('rails_'+zone,ao=False)
 for (ez,axis,fixed,y),spans in edges.items():
  if ez!=zone:continue
  spans.sort();runs=[]
  for a,b in spans:
   if runs and abs(runs[-1][1]-a)<.001:runs[-1]=(runs[-1][0],b)
   else:runs.append((a,b))
  for a,b in runs:
   p=((a+b)/2,y+.95,fixed) if axis=='x' else (fixed,y+.95,(a+b)/2)
   size=(b-a,.10,.10) if axis=='x' else (.10,.10,b-a)
   box('handrail_1m',p,size,'stone',0)
   for k in range(max(1,math.ceil((b-a)/2))+1):
    v=a+(b-a)*k/max(1,math.ceil((b-a)/2))
    box('rail_post',(v,y+.5,fixed) if axis=='x' else (fixed,y+.5,v),(.12,1,.12),'stone',0)
 place('rails_'+zone,zone=zone)
seen=set();todo=[next(iter(cells))]
while todo:
 p=todo.pop()
 if p in seen:continue
 seen.add(p);todo.extend(q for q in [(p[0]+1,p[1]),(p[0]-1,p[1]),(p[0],p[1]+1),(p[0],p[1]-1)] if q in cells and q not in seen)
assert len(cells)-len(seen)<=8,(len(cells),len(seen))
polys=[polys[i] for p,i in cells.items() if p in seen];cells={p:i for i,p in enumerate(p for p in cells if p in seen)}
navzones={z:[] for z in ZONES}
for poly in polys:
 c=[sum(verts[i][k] for i in poly)/4 for k in range(3)];navzones[zone_for(c[0],c[2],c[1])].append(poly)
route=[[-22,1,19],[-22,1,12],[-22,3.25,7.5],[8,3.25,7.5],[8,5.5,3],[-22,5.5,3],[-22,7.75,-1.5],[8,7.75,-1.5],[8,10,-6],[0,10,-6]]
route_length=sum(math.dist(a,b) for a,b in zip(route,route[1:]))
layout={'revision':'B blockout v2 real scale','units':'metres, Y up, north -Z','placements':placements,'zones':ZONES,
 'spawn':route[0],'exit':[-23,1,19.4],'cam0':route[0],'review_points':{'opening':route[0],'mid_hill':route[4],'visitor_center':route[-1]},
 'navigation':{'vertices':verts,'polygons':polys,'zone_polygons':navzones,'cell':step},'route':route,'walk_goals':[route[0],route[4],route[-1]],'route_centerline_m':route_length,
 'stairs':[{'flight':i+1,'lower':s[5],'upper':s[4],'width':3,'run':4.5,'risers':15,'riser_m':.15} for i,s in enumerate(stairs)],
 'camera':{'pitch':43,'yaw':14.5,'width':6.72,'zoom_min':.8,'zoom_max':1.4,'forward_bias_m':2.8},
 'dimensions_m':{'island':[60,40],'museum':[40,9,10],'lighthouse_height':15,'water_tower_height':12,'ferry_length':25,'bench_length':1.5,'bench_seat_height':.45,'railing_height':1,'lamp_height':3.5,'avatar_nominal_height':1.75},
 'sea_size':512,'nav_connected_cells':len(cells),'clearance_m':.25,
 'notes':['v2 real-scale whitebox; colors and detail pending review.','DistantScenery uses a separate viewport with false perspective, not island coordinates.']}
(OUT/'layout.json').write_text(json.dumps(layout,separators=(',',':'))+'\n')
manifest={'generator':'tools/art/source/alcatraz_island/build.py','reference':'landmark_alcatraz_v2.jpg + c_alc2.png','phase':'v2 whitebox','assets':{}}
for name in kit.assets:
 manifest['assets'][name]=kit.export(name,ao_radius=.18)
 print('ALCATRAZ_ASSET',name,manifest['assets'][name],flush=True)
assert sum(manifest['assets'][p['asset']]['triangles'] for p in placements)<=300000
assert len(placements)+1<=80
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
assembly=bpy.data.collections.new('Alcatraz_v2_Assembly');bpy.context.scene.collection.children.link(assembly)
zone_collections={}
for z in ZONES+['DistantScenery']:
 col=bpy.data.collections.new(z);assembly.children.link(col);zone_collections[z]=col
for i,p in enumerate(placements):
 obj=bpy.data.objects.new('%02d_%s'%(i,p['asset']),None);obj.instance_type='COLLECTION';obj.instance_collection=kit.assets[p['asset']]
 obj.location=kit.v(p['position']);obj.rotation_euler.z=p['yaw'];obj.scale=(p['scale'],)*3;zone_collections[p['zone']].objects.link(obj)
for col in kit.assets.values():bpy.context.scene.collection.children.unlink(col)
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'alcatraz_blockout.blend'))
# Retire only former generated GLBs and their imports; do not leave stale assets in the kit.
for file in OUT.glob('*.glb'):
 if file.stem not in kit.assets:
  file.unlink();file.with_suffix('.glb.import').unlink(missing_ok=True)
print('ALCATRAZ_DONE',len(kit.assets),'assets;',len(cells),'cells; route',route_length,flush=True)
