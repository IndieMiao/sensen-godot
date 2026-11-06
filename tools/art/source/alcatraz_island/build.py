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
sys.path.insert(0,str(HERE))
import placeholders
OUT=ROOT/'assets/landmarks/alcatraz_island'
reset_scene(); random.seed(424)
kit=Kit(OUT,{'stone':'b5b6b3','garden':'8d9690','road':'e5e3db','building':'dbdcd7',
 'roof':'acb1b2','glass':'78868a','wood':'b8b3a6','dark':'727d80','bird':'eeede6','bridge':'c76845','far':'b4c2c8'})
placements=[]
ZONES=['DockZone','TerraceZone','SummitZone']
def place(asset,pos=(0,0,0),zone='TerraceZone',yaw=0,scale=1,collision=True):
 p=dict(asset=asset,position=list(pos),zone=zone,yaw=yaw,scale=scale,collision=collision)
 placements.append(p)
 return p
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
kit.begin('alc_museum',ao=False)
box('museum_two_storeys',(0,4.4,0),(40,8.8,10),'building',.05)
box('roof',(0,8.9,0),(40,.2,10),'roof',.02)
box('public_door_frame',(0,1.8,5.1),(2.6,3.6,.2))
box('public_glazed_door',(0,1.65,5.22),(1.8,3.3,.04),'glass',0)
for x in range(-18,19,3):
 for y in [2.3,6.3]:
  if x==0 and y<3:continue
  box('unbarred_window',(x,y,5.03),(1.25,2.15,.04),'glass',.04)
for x in [-19.6,19.6]:box('corner_trim',(x,4.4,5.06),(.4,8.8,.12))
place('alc_museum',(0,10,-13),'SummitZone')
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
placeholders.build(kit,box,prism,place)
placeholders.scatter(place)
kit.begin('gull',ao=False)
kit.ellipsoid('body',(0,.12,0),(.32,.24,.45),'bird',seg=10,rings=6)
kit.ellipsoid('head',(0,.29,-.18),(.19,.19,.19),'bird',seg=8,rings=6)
box('beak',(0,.28,-.29),(.08,.06,.13),'wood',.01)
for p,z in [((-23.6,2,18.2),'DockZone'),((10,4.25,8.7),'TerraceZone'),((-24,11,-7),'SummitZone')]:place('gull',p,z,collision=False)
# World installation: 20 m seaward of the dock spawn. Fake elevation keeps cards in the opening's top edge.
far_anchor=[-22,-.15,39]
yaw=math.radians(14.5);pitch=math.radians(43)
target=[-22-math.sin(yaw)*2.8,1.7,19-math.cos(yaw)*2.8]
def card_mount(screen_x,screen_y):
    z=far_anchor[2];dx=(screen_x+math.sin(yaw)*(z-target[2]))/math.cos(yaw)
    y=target[1]+(screen_y+math.sin(yaw)*math.sin(pitch)*dx+math.cos(yaw)*math.sin(pitch)*(z-target[2]))/math.cos(pitch)
    return [target[0]+dx,y,z]
for asset,sx,sy in [('alc_far_bridge',-2.15,5.2),('alc_far_city',1.1,5.15),('alc_far_hills',0,5.0)]:
    place(asset,card_mount(sx,sy),'FarZone',collision=False)

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
  floor=surface(x,z)
  if floor is None or abs(floor-py)>.3:continue
  if p['asset']=='alc_bench' and abs(x-px)<1 and abs(z-pz)<.6:return True
  if p['asset']=='alc_lamp' and math.hypot(x-px,z-pz)<.35:return True
  if p['asset']=='alc_sign' and math.hypot(x-px,z-pz)<.35:return True
  if p['asset']=='alc_bin' and abs(x-px)<.5 and abs(z-pz)<.5:return True
  if p['asset']=='alc_flowerbed' and abs(x-px)<.95 and abs(z-pz)<.6:return True
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
placeholders.rail_instances(edges,place)
# Static ground is one surface per loading zone; reusable props remain separate prototypes.
for zone,new_name in [('DockZone','alc_ground_dock'),('TerraceZone','alc_ground_terraces'),('SummitZone','alc_ground_summit')]:
    old_names=[p['asset'] for p in placements if p['zone']==zone and p['asset'].startswith(('terrain_','walkways_','stairs_'))]
    kit.begin(new_name,ao=False);combined=kit.current
    for old in old_names:
        collection=kit.assets.pop(old)
        for obj in list(collection.objects):
            collection.objects.unlink(obj);combined.objects.link(obj)
        kit.no_ao.discard(old)
        bpy.data.collections.remove(collection)
    placements[:]=[p for p in placements if p['asset'] not in old_names]
    place(new_name,zone=zone)
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
layout={'revision':'B blockout v4 integration contract','units':'metres, Y up, north -Z','placements':placements,'zones':ZONES,
 'spawn':route[0],'exit':[-23,1,19.4],'cam0':route[0],'review_points':{'opening':route[0],'mid_hill':route[4],'visitor_center':route[-1]},
 'navigation':{'vertices':verts,'polygons':polys,'zone_polygons':navzones,'cell':step},'route':route,'walk_goals':[route[0],route[4],route[-1]],'route_centerline_m':route_length,
 'stairs':[{'flight':i+1,'lower':s[5],'upper':s[4],'width':3,'run':4.5,'risers':15,'riser_m':.15} for i,s in enumerate(stairs)],
 'camera':{'pitch':43,'yaw':14.5,'width':6.72,'zoom_min':1/3,'zoom_max':1.4,'forward_bias_m':2.8},
 'dimensions_m':{'island':[60,40],'museum':[40,9,10],'lighthouse_height':15,'water_tower_height':12,'ferry_length':25,'bench_length':1.5,'bench_seat_height':.45,'railing_height':1,'lamp_height':3.5,'avatar_nominal_height':1.75},
 'sea_size':512,'nav_connected_cells':len(cells),'clearance_m':.25,
 'notes':['v4 placeholders for delegated pieces; final art pending Nov 8/9.','FarZone cards mount 20m seaward, with documented false-perspective elevation and depth.']}
# Public integration contract follows tea_house's camera/spawn/anchors/boundaries fields.
lod_groups=[]
for asset in ['alc_museum','alc_lighthouse','alc_watertower']:
    lod_groups.append({'name':asset,'near':asset,'far':asset+'_far','switch_distance_m':55,'margin_m':0,'far_placeholder':True})
asset_instance_counts=defaultdict(int)
for i,p in enumerate(placements):
    p['name']='%s_%03d'%(p['asset'],asset_instance_counts[p['asset']])
    asset_instance_counts[p['asset']]+=1
    p['rotation_degrees']=[0,math.degrees(p['yaw']),0]
    p['scale']=p['scale'] if isinstance(p['scale'],list) else [p['scale']]*3
    p['multimesh']=p['asset'] in placeholders.REPEATED
    p['placeholder']=p['asset'] in placeholders.OWNERS
    p['owner']=placeholders.OWNERS.get(p['asset'],'马可波罗')
    if p['asset'] in [g['near'] for g in lod_groups]:p['lod_group']=p['asset']
used={i for p in polys for i in p};navpoints=[verts[i] for i in used]
layout['walk_bounds']={'min':[min(p[k] for p in navpoints) for k in range(3)],'max':[max(p[k] for p in navpoints) for k in range(3)],'note':'Outer bounds only; walkability comes from navigation polygons.'}
layout['axes']='Godot Y-up, +X east, +Z south/dock; Blender (x,-z,y)'
layout['floor_y']=1.0;layout['footprint_m']=[60,40]
layout['anchors']=[{'name':name,'position':pos,'yaw_degrees':0 if name=='spawn' else 180} for name,pos in [('spawn',layout['spawn']),('exit',layout['exit'])]]
layout['anchors']+=[{'name':'badge_exit','position':[-23,1.45,19.4],'yaw_degrees':180},{'name':'cam_default','position':target,'yaw_degrees':14.5,'pitch_degrees':43,'width_m':6.72},{'name':'far_offshore','position':far_anchor,'yaw_degrees':0}]
direction=[math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch)]
campos=[target[k]+direction[k]*11 for k in range(3)]
back=max(0,1-(campos[1]-6.72*(800/360)/2*math.cos(pitch)-28)/math.sin(pitch))
layout['camera'].update({'position':[campos[k]+direction[k]*back for k in range(3)],'target':target,'size':6.72,'default_zoom':1,'max_view_width_m':20.16,'zoom_out_factor':3,'pan_bounds':[-50,50,-40,40],
 'wide_view':{'yaw_degrees':60,'target':[-5,17.75,-8],'target_offset_from_player':[-5,7.75,-2],'size':20.16}})
layout['boundaries']=[{'name':'WestBoundary','size':[.2,36,40],'at':[-30.1,17.85,0]},{'name':'EastBoundary','size':[.2,36,40],'at':[30.1,17.85,0]},
 {'name':'NorthBoundary','size':[60,36,.2],'at':[0,17.85,-20.1]},{'name':'SouthBoundary','size':[60,36,.2],'at':[0,17.85,20.1]}]
layout['lod_groups']=lod_groups
layout['far_anchor']=far_anchor
layout['far_zone']={'node':'FarZone','anchor':far_anchor,'projection':'camera-facing XY cards, fake elevation, depth behind opaque island; local front +Z','render_depth_fraction':.92}
layout['instances']=[{k:p[k] for k in ['name','asset','zone','position','rotation_degrees','scale','basis_columns','slope_rise_m','owner','placeholder'] if k in p} for p in placements if p['multimesh']]
layout['interest_points']=[{'name':p['name'],'asset':p['asset'],'position':p['position'],'zone':p['zone']} for p in placements if p['asset'] in placeholders.REPEATED and p['asset'] not in ['alc_rail_straight','alc_rail_corner','alc_curb']]
layout['assets']=[{'name':name,'file':name+'.glb','placeholder':name in placeholders.OWNERS,'owner':placeholders.OWNERS.get(name,'马可波罗'),'pivot':'ground centre; +Z front','cast_shadow':name not in ['alc_curb','alc_lamp','alc_bin','alc_sign','alc_rail_corner','alc_flowerbed','alc_rock_a','alc_rock_b','alc_rock_c','alc_shrub','alc_grass_tuft','ferry','gull'] and not name.startswith('alc_far_') and not name.endswith('_far'),'material':'vertex_color_placeholder' if name in placeholders.OWNERS else 'vertex_color'} for name in kit.assets]
for asset in layout['assets']:
    if asset['name'] in ['alc_grass_tuft','alc_shrub','alc_flowerbed','alc_bin','alc_rail_corner']:
        asset['max_view_width_m']=8.0
(OUT/'placement_points.json').write_text(json.dumps({'units':'metres','axes':layout['axes'],'instances':layout['instances']},ensure_ascii=False,indent=2)+'\n')
(OUT/'layout.json').write_text(json.dumps(layout,separators=(',',':'))+'\n')
manifest={'generator':'tools/art/source/alcatraz_island/build.py','reference':'landmark_alcatraz_v2.jpg + c_alc2.png','phase':'v4 whitebox integration','assets':{}}
for name in kit.assets:
 manifest['assets'][name]=kit.export(name,ao_radius=.18)
 print('ALCATRAZ_ASSET',name,manifest['assets'][name],flush=True)
assert sum(manifest['assets'][p['asset']]['triangles'] for p in placements)<=300000
assert len(kit.assets)<=80
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
assembly=bpy.data.collections.new('Alcatraz_v4_Assembly');bpy.context.scene.collection.children.link(assembly)
zone_collections={}
for z in ZONES+['FarZone']:
 col=bpy.data.collections.new(z);assembly.children.link(col);zone_collections[z]=col
for i,p in enumerate(placements):
 obj=bpy.data.objects.new('%02d_%s'%(i,p['asset']),None);obj.instance_type='COLLECTION';obj.instance_collection=kit.assets[p['asset']]
 obj.location=kit.v(p['position']);obj.rotation_euler.z=p['yaw'];obj.scale=(p['scale'][0],p['scale'][2],p['scale'][1]);zone_collections[p['zone']].objects.link(obj)
 if 'basis_columns' in p:
  from mathutils import Matrix
  c=Matrix(((1,0,0),(0,0,-1),(0,1,0)));b=Matrix(p['basis_columns']).transposed()
  obj.matrix_world=(c@b@c.inverted()).to_4x4();obj.location=kit.v(p['position'])
library=bpy.data.scenes.new('Alcatraz_Module_Library')
for col in kit.assets.values():
 library.collection.children.link(col)
 bpy.context.scene.collection.children.unlink(col)
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'alcatraz_blockout.blend'))
# Retire only former generated GLBs and their imports; do not leave stale assets in the kit.
for file in OUT.glob('*.glb'):
 if file.stem not in kit.assets:
  file.unlink();file.with_suffix('.glb.import').unlink(missing_ok=True)
print('ALCATRAZ_DONE',len(kit.assets),'assets;',len(cells),'cells; route',route_length,flush=True)
